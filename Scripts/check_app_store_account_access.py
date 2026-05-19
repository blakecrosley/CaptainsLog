#!/usr/bin/env python3
"""Read-only App Store Connect API account-access visibility check."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.dont_write_bytecode = True

import check_app_store_connect_record as asc  # noqa: E402


class AccountAccessError(Exception):
    pass


def fail(message: str) -> None:
    raise AccountAccessError(message)


def build_token() -> str:
    asc.load_local_env_defaults()
    key_id = asc.env_with_alias("APP_STORE_CONNECT_API_KEY", "ASC_KEY_ID")
    issuer_id = asc.env_with_alias("APP_STORE_CONNECT_API_ISSUER", "ASC_ISSUER_ID")
    if len(key_id) != 10 or not key_id.isalnum():
        fail("APP_STORE_CONNECT_API_KEY/ASC_KEY_ID should be a 10-character key ID")
    if not issuer_id:
        fail("APP_STORE_CONNECT_API_ISSUER/ASC_ISSUER_ID is required")
    p8_path = asc.resolve_p8_path(key_id)
    return asc.build_token(key_id, issuer_id, p8_path)


def fetch_users(token: str) -> list[dict[str, Any]]:
    payload = asc.api_get(
        token,
        "/v1/users",
        {
            "fields[users]": "roles,allAppsVisible,provisioningAllowed",
            "limit": "200",
        },
    )
    users = payload.get("data", [])
    return users if isinstance(users, list) else []


def fetch_apps_page(token: str) -> list[dict[str, Any]]:
    payload = asc.api_get(
        token,
        "/v1/apps",
        {
            "fields[apps]": "bundleId",
            "limit": "200",
        },
    )
    apps = payload.get("data", [])
    return apps if isinstance(apps, list) else []


def collect_status(token: str) -> dict[str, Any]:
    users = fetch_users(token)
    apps = fetch_apps_page(token)
    role_counts: Counter[str] = Counter()
    all_apps_visible_counts: Counter[str] = Counter()
    provisioning_allowed_counts: Counter[str] = Counter()

    for user in users:
        attributes = user.get("attributes", {})
        for role in attributes.get("roles") or []:
            role_counts[str(role)] += 1
        all_apps_visible_counts[str(attributes.get("allAppsVisible"))] += 1
        provisioning_allowed_counts[str(attributes.get("provisioningAllowed"))] += 1

    return {
        "usersVisibleCount": len(users),
        "appsVisibleCount": len(apps),
        "appsVisibleCountLimit": 200,
        "rolesVisible": dict(sorted(role_counts.items())),
        "cloudManagedAppDistributionRoleVisible": "CLOUD_MANAGED_APP_DISTRIBUTION" in role_counts,
        "allAppsVisibleCounts": dict(sorted(all_apps_visible_counts.items())),
        "provisioningAllowedCounts": dict(sorted(provisioning_allowed_counts.items())),
        "privacyBoundary": (
            "User names, emails, app names, bundle IDs, resource IDs, and API-key material are "
            "intentionally not printed."
        ),
        "limits": (
            "This proves the selected API credential can read account user visibility and list "
            "at least one page of existing apps. "
            "Visible role aggregates are not selected-key proof. This does not prove the selected "
            "key can create app records, create signing assets, or use cloud-managed distribution "
            "certificates."
        ),
    }


def print_status(status: dict[str, Any]) -> None:
    print("Captain's Log App Store Connect account access")
    print("[info] User names, emails, app names, bundle IDs, IDs, and API-key material are intentionally omitted.")
    print(f"[ok] visible user count: {status['usersVisibleCount']}")
    print(f"[ok] visible app count page: {status['appsVisibleCount']} of limit {status['appsVisibleCountLimit']}")
    roles = status["rolesVisible"]
    if roles:
        print("[ok] visible roles: " + ", ".join(f"{role}:{count}" for role, count in roles.items()))
    else:
        print("[warn] no visible roles reported")
    if status["cloudManagedAppDistributionRoleVisible"]:
        print("[ok] explicit CLOUD_MANAGED_APP_DISTRIBUTION role is visible in account aggregates")
    else:
        print(
            "[info] explicit CLOUD_MANAGED_APP_DISTRIBUTION role is not visible in account aggregates; "
            "exportArchive remains the cloud-signing authority"
        )
    print(
        "[info] all-apps-visible aggregate: "
        + ", ".join(f"{key}:{value}" for key, value in status["allAppsVisibleCounts"].items())
    )
    print(
        "[info] provisioning-allowed aggregate: "
        + ", ".join(f"{key}:{value}" for key, value in status["provisioningAllowedCounts"].items())
    )
    print("[info] This is read-only account visibility evidence, not signing/export proof.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Print machine-readable status")
    args = parser.parse_args()

    token = build_token()
    status = collect_status(token)
    if args.json:
        print(json.dumps(status, indent=2, sort_keys=True))
    else:
        print_status(status)
    return 0 if status["usersVisibleCount"] > 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AccountAccessError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
    except asc.CheckError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
