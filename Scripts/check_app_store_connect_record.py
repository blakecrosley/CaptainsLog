#!/usr/bin/env python3
"""Check App Store Connect app-record and bundle-ID status for Captain's Log."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

try:
    import jwt
except ImportError:  # pragma: no cover - environment guard
    jwt = None


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_BUNDLE_ID = "com.blakecrosley.captainslog"
API_BASE = "https://api.appstoreconnect.apple.com"


class CheckError(Exception):
    pass


def fail(message: str) -> None:
    raise CheckError(message)


def git_root_for_path(path: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(path.parent), "rev-parse", "--show-toplevel"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return result.stdout.strip()
    return ""


def default_p8_path_for_key(key_id: str) -> Path | None:
    dirs = [
        Path.home() / "private_keys",
        Path.home() / ".private_keys",
        Path.home() / ".appstoreconnect" / "private_keys",
    ]
    if os.environ.get("API_PRIVATE_KEYS_DIR"):
        dirs.append(Path(os.environ["API_PRIVATE_KEYS_DIR"]))

    filename = f"AuthKey_{key_id}.p8"
    for directory in dirs:
        candidate = directory / filename
        if candidate.is_file():
            return candidate
    return None


def env_with_alias(primary: str, alias: str) -> str:
    return os.environ.get(primary) or os.environ.get(alias, "")


def resolve_p8_path(key_id: str) -> Path:
    direct_p8_path = env_with_alias("APP_STORE_CONNECT_P8_FILE", "ASC_KEY_PATH")
    if direct_p8_path:
        p8_path = Path(direct_p8_path).expanduser()
    else:
        p8_path = default_p8_path_for_key(key_id) or Path()

    if not p8_path:
        fail(
            "APP_STORE_CONNECT_P8_FILE/ASC_KEY_PATH is not set and "
            "AuthKey_<key>.p8 was not found in supported private-key directories"
        )

    p8_path = p8_path.resolve()
    if not p8_path.is_file():
        fail(f"APP_STORE_CONNECT_P8_FILE/ASC_KEY_PATH does not exist: {p8_path}")
    if ROOT_DIR in [p8_path, *p8_path.parents]:
        fail(f"App Store Connect .p8 key file must live outside this repo: {p8_path}")
    git_root = git_root_for_path(p8_path)
    if git_root:
        fail(f"App Store Connect .p8 key file must live outside any git working tree: {git_root}")
    if not os.access(p8_path, os.R_OK):
        fail(f"App Store Connect .p8 key file is not readable: {p8_path}")
    expected_name = f"AuthKey_{key_id}.p8"
    if p8_path.name != expected_name and os.environ.get("CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME") != "1":
        fail(
            "APP_STORE_CONNECT_P8_FILE/ASC_KEY_PATH basename should be "
            f"{expected_name}. Set CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1 only after manual verification."
        )
    return p8_path


def build_token(key_id: str, issuer_id: str, p8_path: Path) -> str:
    if jwt is None:
        fail("Python module PyJWT is required for App Store Connect REST checks")
    private_key = p8_path.read_bytes()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": now - 30, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def api_get(token: str, path: str, params: dict[str, str]) -> dict[str, Any]:
    query = urllib.parse.urlencode(params)
    request = urllib.request.Request(
        f"{API_BASE}{path}?{query}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = {"errors": [{"detail": body[:500]}]}
        detail = "; ".join(error.get("detail", "unknown error") for error in payload.get("errors", []))
        fail(f"App Store Connect API request failed with HTTP {exc.code}: {detail}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument(
        "--require",
        choices=("both", "app-record", "bundle-id"),
        default="both",
        help="Choose which remote record type must exist for a successful exit.",
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable status")
    args = parser.parse_args()

    key_id = env_with_alias("APP_STORE_CONNECT_API_KEY", "ASC_KEY_ID")
    issuer_id = env_with_alias("APP_STORE_CONNECT_API_ISSUER", "ASC_ISSUER_ID")
    if len(key_id) != 10 or not key_id.isalnum():
        fail("APP_STORE_CONNECT_API_KEY/ASC_KEY_ID should be a 10-character key ID")
    if not issuer_id:
        fail("APP_STORE_CONNECT_API_ISSUER/ASC_ISSUER_ID is required")

    p8_path = resolve_p8_path(key_id)
    token = build_token(key_id, issuer_id, p8_path)

    app_payload = api_get(
        token,
        "/v1/apps",
        {"filter[bundleId]": args.bundle_id, "fields[apps]": "bundleId,name,sku,primaryLocale"},
    )
    bundle_payload = api_get(
        token,
        "/v1/bundleIds",
        {"filter[identifier]": args.bundle_id, "fields[bundleIds]": "identifier,name,platform,seedId"},
    )

    apps = app_payload.get("data", [])
    bundle_ids = bundle_payload.get("data", [])
    result = {
        "bundleId": args.bundle_id,
        "appRecordCount": len(apps),
        "bundleIdRecordCount": len(bundle_ids),
        "apps": [
            {
                "id": app.get("id"),
                "bundleId": app.get("attributes", {}).get("bundleId"),
                "name": app.get("attributes", {}).get("name"),
                "sku": app.get("attributes", {}).get("sku"),
                "primaryLocale": app.get("attributes", {}).get("primaryLocale"),
            }
            for app in apps
        ],
        "bundleIds": [
            {
                "id": bundle.get("id"),
                "identifier": bundle.get("attributes", {}).get("identifier"),
                "name": bundle.get("attributes", {}).get("name"),
                "platform": bundle.get("attributes", {}).get("platform"),
                "seedId": bundle.get("attributes", {}).get("seedId"),
            }
            for bundle in bundle_ids
        ],
    }

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print("Captain's Log App Store Connect record status")
        print(f"Bundle ID: {args.bundle_id}")
        if bundle_ids:
            bundle = result["bundleIds"][0]
            print(f"[ok] Developer Portal bundle ID exists: {bundle['identifier']} ({bundle['id']})")
        else:
            print("[fail] Developer Portal bundle ID is missing")
        if apps:
            app = result["apps"][0]
            print(f"[ok] App Store Connect app record exists: {app['name']} ({app['id']})")
            print(f"[ok] App record bundle ID: {app['bundleId']}")
            print(f"[ok] App record SKU: {app['sku']}")
        else:
            print("[fail] App Store Connect app record is missing or not visible to this API key")

    if args.require == "both":
        return 0 if apps and bundle_ids else 1
    if args.require == "app-record":
        return 0 if apps else 1
    return 0 if bundle_ids else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CheckError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
