#!/usr/bin/env python3
"""Check App Store Connect app-record and bundle-ID status for Captain's Log."""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import shlex
from pathlib import Path
from typing import Any

try:
    import jwt
except ImportError:  # pragma: no cover - environment guard
    jwt = None


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_BUNDLE_ID = "com.blakecrosley.captainslog"
DEFAULT_APP_NAME = "Captain's Log"
DEFAULT_SKU = "captainslog-ios"
API_BASE = "https://api.appstoreconnect.apple.com"
APP_ENTITLEMENTS = ROOT_DIR / "CaptainsLog" / "App" / "CaptainsLog.entitlements"
REQUIRED_CAPABILITY_BY_ENTITLEMENT = {
    "com.apple.developer.ubiquity-kvstore-identifier": "ICLOUD",
}
LOCAL_ENV_NAMES = (
    "APP_STORE_CONNECT_API_KEY",
    "APP_STORE_CONNECT_API_ISSUER",
    "APP_STORE_CONNECT_P8_FILE",
    "APP_STORE_CONNECT_PROVIDER_PUBLIC_ID",
    "APP_STORE_CONNECT_APPLE_ID",
    "APP_STORE_CONNECT_DELIVERY_ID",
    "ASC_KEY_ID",
    "ASC_ISSUER_ID",
    "ASC_KEY_PATH",
    "API_PRIVATE_KEYS_DIR",
    "CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME",
)


class CheckError(Exception):
    pass


def fail(message: str) -> None:
    raise CheckError(message)


def load_local_env_file(path: Path) -> None:
    if not path.is_file():
        return

    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            parts = shlex.split(stripped, comments=True, posix=True)
        except ValueError as exc:
            fail(f"Could not parse local App Store Connect env line in {path}: {exc}")
        if not parts:
            continue
        if parts[0] == "export":
            parts = parts[1:]
        for part in parts:
            if "=" not in part:
                continue
            name, value = part.split("=", 1)
            if name in LOCAL_ENV_NAMES:
                os.environ[name] = value


def load_local_env_defaults() -> None:
    explicit_env_file = os.environ.get("CAPTAINS_LOG_APP_STORE_CONNECT_ENV_FILE")
    if explicit_env_file:
        path = Path(explicit_env_file).expanduser()
        if not path.is_file():
            fail(f"CAPTAINS_LOG_APP_STORE_CONNECT_ENV_FILE does not exist: {path}")
        load_local_env_file(path)
        return

    load_local_env_file(ROOT_DIR / "AppStoreConnectEnv.local.sh")
    load_local_env_file(ROOT_DIR / "Docs" / "AppStoreConnectEnv.local.sh")


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


def api_get(token: str, path: str, params: dict[str, str], allowed_missing_statuses: set[int] | None = None) -> dict[str, Any]:
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
        if allowed_missing_statuses and exc.code in allowed_missing_statuses:
            return {"data": None, "errors": payload.get("errors", [])}
        detail = "; ".join(error.get("detail", "unknown error") for error in payload.get("errors", []))
        fail(f"App Store Connect API request failed with HTTP {exc.code}: {detail}")


def required_capabilities_from_entitlements(path: Path = APP_ENTITLEMENTS) -> list[dict[str, str]]:
    if not path.is_file():
        return []

    with path.open("rb") as handle:
        entitlements = plistlib.load(handle)

    required: list[dict[str, str]] = []
    for entitlement_key, capability_type in REQUIRED_CAPABILITY_BY_ENTITLEMENT.items():
        if entitlement_key in entitlements:
            required.append(
                {
                    "entitlement": entitlement_key,
                    "capabilityType": capability_type,
                }
            )
    return required


def resolve_entitlements_path(path_text: str) -> Path:
    path = Path(path_text).expanduser()
    if not path.is_absolute():
        path = ROOT_DIR / path
    return path.resolve()


def fetch_bundle_capabilities(token: str, bundle_id_resource_id: str) -> list[dict[str, Any]]:
    payload = api_get(
        token,
        f"/v1/bundleIds/{bundle_id_resource_id}/bundleIdCapabilities",
        {"fields[bundleIdCapabilities]": "capabilityType,settings"},
    )
    return [
        {
            "id": capability.get("id"),
            "capabilityType": capability.get("attributes", {}).get("capabilityType"),
            "settings": capability.get("attributes", {}).get("settings", []),
        }
        for capability in payload.get("data", [])
    ]


def exact_bundle_matches(bundle_ids: list[dict[str, Any]], identifier: str) -> list[dict[str, Any]]:
    return [
        bundle
        for bundle in bundle_ids
        if bundle.get("attributes", {}).get("identifier") == identifier
    ]


def exact_app_matches(apps: list[dict[str, Any]], bundle_id: str) -> list[dict[str, Any]]:
    return [
        app
        for app in apps
        if app.get("attributes", {}).get("bundleId") == bundle_id
    ]


def fetch_app_for_bundle(token: str, bundle_resource_id: str) -> dict[str, Any] | None:
    payload = api_get(
        token,
        f"/v1/bundleIds/{bundle_resource_id}/app",
        {"fields[apps]": "bundleId,name,sku,primaryLocale"},
        allowed_missing_statuses={404},
    )
    app = payload.get("data")
    return app if isinstance(app, dict) else None


def fetch_apps_by_filter(token: str, filter_name: str, value: str) -> list[dict[str, Any]]:
    if not value:
        return []

    payload = api_get(
        token,
        "/v1/apps",
        {
            f"filter[{filter_name}]": value,
            "fields[apps]": "bundleId,name,sku,primaryLocale",
        },
    )
    apps = payload.get("data", [])
    return apps if isinstance(apps, list) else []


def app_summary(app: dict[str, Any]) -> dict[str, Any]:
    attributes = app.get("attributes", {})
    return {
        "id": app.get("id"),
        "bundleId": attributes.get("bundleId"),
        "name": attributes.get("name"),
        "sku": attributes.get("sku"),
        "primaryLocale": attributes.get("primaryLocale"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--expected-name", default=DEFAULT_APP_NAME)
    parser.add_argument("--expected-sku", default=DEFAULT_SKU)
    parser.add_argument(
        "--entitlements",
        default=str(APP_ENTITLEMENTS.relative_to(ROOT_DIR)),
        help="Entitlements plist to use when deriving required Developer Portal capabilities.",
    )
    parser.add_argument(
        "--skip-app-record",
        action="store_true",
        help="Skip the App Store Connect app-record lookup when only Developer Portal bundle state is required.",
    )
    parser.add_argument(
        "--require",
        choices=("all", "both", "app-record", "bundle-id", "capabilities"),
        default="both",
        help="Choose which remote record type must exist for a successful exit.",
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable status")
    args = parser.parse_args()
    if args.skip_app_record and args.require in ("all", "both", "app-record"):
        fail("--skip-app-record can only be used with --require bundle-id or --require capabilities")

    load_local_env_defaults()

    key_id = env_with_alias("APP_STORE_CONNECT_API_KEY", "ASC_KEY_ID")
    issuer_id = env_with_alias("APP_STORE_CONNECT_API_ISSUER", "ASC_ISSUER_ID")
    if len(key_id) != 10 or not key_id.isalnum():
        fail("APP_STORE_CONNECT_API_KEY/ASC_KEY_ID should be a 10-character key ID")
    if not issuer_id:
        fail("APP_STORE_CONNECT_API_ISSUER/ASC_ISSUER_ID is required")

    p8_path = resolve_p8_path(key_id)
    token = build_token(key_id, issuer_id, p8_path)

    app_payload = {"data": []}
    sku_apps: list[dict[str, Any]] = []
    name_apps: list[dict[str, Any]] = []
    if not args.skip_app_record:
        app_payload = api_get(
            token,
            "/v1/apps",
            {"filter[bundleId]": args.bundle_id, "fields[apps]": "bundleId,name,sku,primaryLocale"},
        )
        sku_apps = fetch_apps_by_filter(token, "sku", args.expected_sku)
        name_apps = fetch_apps_by_filter(token, "name", args.expected_name)
    bundle_payload = api_get(
        token,
        "/v1/bundleIds",
        {"filter[identifier]": args.bundle_id, "fields[bundleIds]": "identifier,name,platform,seedId"},
    )

    app_record_lookup_method = "skipped"
    apps = exact_app_matches(app_payload.get("data", []), args.bundle_id)
    bundle_ids = exact_bundle_matches(bundle_payload.get("data", []), args.bundle_id)
    capabilities: list[dict[str, Any]] = []
    entitlements_path = resolve_entitlements_path(args.entitlements)
    required_capabilities = required_capabilities_from_entitlements(entitlements_path)
    if bundle_ids:
        capabilities = fetch_bundle_capabilities(token, bundle_ids[0].get("id", ""))
        if not args.skip_app_record:
            app_from_bundle = fetch_app_for_bundle(token, bundle_ids[0].get("id", ""))
            if app_from_bundle:
                apps = [app_from_bundle]
                app_record_lookup_method = "bundle-id-relationship"
            elif apps:
                app_record_lookup_method = "app-list-filter"
            else:
                app_record_lookup_method = "bundle-id-relationship-empty"
    elif not args.skip_app_record:
        app_record_lookup_method = "app-list-filter"
    capability_types = {capability.get("capabilityType") for capability in capabilities}
    missing_required_capabilities = [
        required
        for required in required_capabilities
        if required.get("capabilityType") not in capability_types
    ]
    app_summaries = [app_summary(app) for app in apps]
    app_record_metadata_mismatches: list[dict[str, Any]] = []
    if app_summaries:
        app = app_summaries[0]
        if app.get("sku") != args.expected_sku:
            app_record_metadata_mismatches.append(
                {"field": "sku", "expected": args.expected_sku, "actual": app.get("sku")}
            )
        if app.get("name") != args.expected_name:
            app_record_metadata_mismatches.append(
                {"field": "name", "expected": args.expected_name, "actual": app.get("name")}
            )
    result = {
        "bundleId": args.bundle_id,
        "entitlementsPath": str(entitlements_path),
        "appRecordCheckSkipped": args.skip_app_record,
        "appRecordLookupMethod": app_record_lookup_method,
        "appRecordCount": len(apps),
        "bundleIdRecordCount": len(bundle_ids),
        "bundleCapabilityCount": len(capabilities),
        "expectedAppName": args.expected_name,
        "expectedSku": args.expected_sku,
        "apps": app_summaries,
        "appRecordMetadataMatches": bool(app_summaries) and not app_record_metadata_mismatches,
        "appRecordMetadataMismatches": app_record_metadata_mismatches,
        "expectedSkuAppRecordCount": len(sku_apps),
        "expectedSkuApps": [app_summary(app) for app in sku_apps],
        "expectedNameAppRecordCount": len(name_apps),
        "expectedNameApps": [app_summary(app) for app in name_apps],
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
        "bundleCapabilities": capabilities,
        "requiredCapabilities": required_capabilities,
        "missingRequiredCapabilities": missing_required_capabilities,
    }

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print("Captain's Log App Store Connect record status")
        print(f"Bundle ID: {args.bundle_id}")
        print(f"Entitlements: {entitlements_path}")
        if bundle_ids:
            bundle = result["bundleIds"][0]
            print(f"[ok] Developer Portal bundle ID exists: {bundle['identifier']} ({bundle['id']})")
        else:
            print("[fail] Developer Portal bundle ID is missing")
        if args.skip_app_record:
            print("[info] App Store Connect app record check skipped")
        else:
            print(f"[info] App record lookup method: {app_record_lookup_method}")
            print(f"[info] Expected app SKU visible matches: {len(sku_apps)} for {args.expected_sku}")
            print(f"[info] Expected app name visible matches: {len(name_apps)} for {args.expected_name}")
            if apps:
                app = result["apps"][0]
                print(f"[ok] App Store Connect app record exists: {app['name']} ({app['id']})")
                print(f"[ok] App record bundle ID: {app['bundleId']}")
                print(f"[ok] App record SKU: {app['sku']}")
                if app_record_metadata_mismatches:
                    for mismatch in app_record_metadata_mismatches:
                        print(
                            f"[fail] App record {mismatch['field']} is {mismatch.get('actual') or 'missing'}, "
                            f"expected {mismatch['expected']}"
                        )
                else:
                    print("[ok] App record name and SKU match expected release metadata")
            else:
                print("[fail] App Store Connect app record is missing or not visible to this API key")
        if bundle_ids and required_capabilities:
            for required in required_capabilities:
                capability_type = required["capabilityType"]
                entitlement_key = required["entitlement"]
                if capability_type in capability_types:
                    print(f"[ok] Required bundle capability enabled: {capability_type} for {entitlement_key}")
                else:
                    print(f"[fail] Required bundle capability missing: {capability_type} for {entitlement_key}")

    if args.require == "all":
        return 0 if apps and bundle_ids and not missing_required_capabilities and not app_record_metadata_mismatches else 1
    if args.require == "both":
        return 0 if apps and bundle_ids and not app_record_metadata_mismatches else 1
    if args.require == "app-record":
        return 0 if apps and not app_record_metadata_mismatches else 1
    if args.require == "capabilities":
        return 0 if bundle_ids and not missing_required_capabilities else 1
    return 0 if bundle_ids else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CheckError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
