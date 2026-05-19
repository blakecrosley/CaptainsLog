#!/usr/bin/env python3
"""Plan or create Developer Portal bundle IDs and capabilities for platform targets."""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ROOT_DIR = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.dont_write_bytecode = True

import check_app_store_connect_record as asc  # noqa: E402


TEAM_ID = "M4WTLM6RAQ"
IOS_BUNDLE_ID = "com.blakecrosley.captainslog"

TARGETS = {
    "macos": {
        "label": "native Mac",
        "bundle_id": "com.blakecrosley.captainslog.mac",
        "name": "XC com blakecrosley captainslog mac",
        "platform": "UNIVERSAL",
        "entitlements": ROOT_DIR / "CaptainsLog" / "App" / "CaptainsLog.entitlements",
        "requires_separate_record_confirmation": True,
    },
    "watchos": {
        "label": "Apple Watch",
        "bundle_id": "com.blakecrosley.captainslog.watchkitapp",
        "name": "XC com blakecrosley captainslog watchkitapp",
        "platform": "UNIVERSAL",
        "entitlements": ROOT_DIR / "CaptainsLogCompanion" / "CaptainsLogCompanion.entitlements",
    },
    "tvos": {
        "label": "Apple TV",
        "bundle_id": "com.blakecrosley.captainslog.tv",
        "name": "XC com blakecrosley captainslog tv",
        "platform": "UNIVERSAL",
        "entitlements": ROOT_DIR / "CaptainsLogCompanion" / "CaptainsLogCompanion.entitlements",
        "requires_separate_record_confirmation": True,
    },
}


class EnsureError(Exception):
    pass


def fail(message: str) -> None:
    raise EnsureError(message)


def api_post(token: str, path: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        f"{asc.API_BASE}{path}",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="POST",
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
        fail(f"App Store Connect API POST {path} failed with HTTP {exc.code}: {detail}")


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


def find_bundle(token: str, bundle_id: str) -> dict[str, Any] | None:
    payload = asc.api_get(
        token,
        "/v1/bundleIds",
        {"filter[identifier]": bundle_id, "fields[bundleIds]": "identifier,name,platform,seedId"},
    )
    matches = asc.exact_bundle_matches(payload.get("data", []), bundle_id)
    return matches[0] if matches else None


def create_bundle(token: str, target: dict[str, Any]) -> dict[str, Any]:
    payload = {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": target["bundle_id"],
                "name": target["name"],
                "platform": target["platform"],
            },
        }
    }
    return api_post(token, "/v1/bundleIds", payload)["data"]


def settings_for_capability(capability_type: str) -> list[dict[str, Any]]:
    if capability_type == "ICLOUD":
        return [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6", "enabled": True}]}]
    return []


def enable_capability(token: str, bundle_resource_id: str, capability_type: str) -> dict[str, Any]:
    attributes: dict[str, Any] = {"capabilityType": capability_type}
    settings = settings_for_capability(capability_type)
    if settings:
        attributes["settings"] = settings
    payload = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": attributes,
            "relationships": {
                "bundleId": {
                    "data": {
                        "type": "bundleIds",
                        "id": bundle_resource_id,
                    }
                }
            },
        }
    }
    return api_post(token, "/v1/bundleIdCapabilities", payload)["data"]


def existing_capability_types(token: str, bundle_resource_id: str) -> set[str]:
    capabilities = asc.fetch_bundle_capabilities(token, bundle_resource_id)
    return {capability.get("capabilityType") for capability in capabilities if capability.get("capabilityType")}


def verify_target_state(token: str, name: str, attempts: int = 3, delay_seconds: int = 2) -> dict[str, Any]:
    target = TARGETS[name]
    required = asc.required_capabilities_from_entitlements(Path(target["entitlements"]))
    result: dict[str, Any] = {
        "bundleId": target["bundle_id"],
        "expectedSeedId": TEAM_ID,
        "requiredCapabilities": [item["capabilityType"] for item in required],
        "verified": False,
    }

    for attempt in range(1, attempts + 1):
        bundle = find_bundle(token, target["bundle_id"])
        result["attempts"] = attempt
        if not bundle:
            result["bundleExists"] = False
            result["reason"] = "bundle ID is missing or not visible"
        else:
            bundle_id = bundle["id"]
            seed_id = bundle.get("attributes", {}).get("seedId")
            capability_types = existing_capability_types(token, bundle_id)
            missing_capabilities = [
                item["capabilityType"] for item in required if item["capabilityType"] not in capability_types
            ]
            result.update(
                {
                    "bundleExists": True,
                    "bundleResourceId": bundle_id,
                    "seedId": seed_id,
                    "enabledCapabilities": sorted(capability_types),
                    "missingCapabilities": missing_capabilities,
                    "verified": seed_id == TEAM_ID and not missing_capabilities,
                }
            )
            if result["verified"]:
                result.pop("reason", None)
                return result
            if seed_id != TEAM_ID:
                result["reason"] = f"expected seedId {TEAM_ID}, got {seed_id or 'unknown'}"
            else:
                result["reason"] = "required capabilities are missing"

        if attempt < attempts:
            time.sleep(delay_seconds)
    return result


def target_names(selected: list[str]) -> list[str]:
    if not selected or "all" in selected:
        return list(TARGETS)
    unknown = sorted(set(selected) - set(TARGETS))
    if unknown:
        fail(f"Unknown target(s): {', '.join(unknown)}")
    return selected


def targets_requiring_separate_record_confirmation(names: list[str]) -> list[str]:
    return [name for name in names if TARGETS[name].get("requires_separate_record_confirmation")]


def confirm_team_for_apply(token: str, confirm_team: str) -> dict[str, Any]:
    if confirm_team != TEAM_ID:
        fail(f"--confirm-team must be {TEAM_ID} before --apply can mutate Apple account state")

    bundle = find_bundle(token, IOS_BUNDLE_ID)
    if not bundle:
        fail(f"Cannot confirm team context because {IOS_BUNDLE_ID} is missing or not visible")

    seed_id = bundle.get("attributes", {}).get("seedId")
    if seed_id != TEAM_ID:
        fail(f"Expected {IOS_BUNDLE_ID} seedId {TEAM_ID}, but App Store Connect returned {seed_id or 'unknown'}")
    return bundle


def process_target(token: str, name: str, apply: bool) -> dict[str, Any]:
    target = TARGETS[name]
    required = asc.required_capabilities_from_entitlements(Path(target["entitlements"]))
    result: dict[str, Any] = {
        "target": name,
        "label": target["label"],
        "bundleId": target["bundle_id"],
        "platform": target["platform"],
        "requiresSeparatePlatformRecordConfirmation": bool(target.get("requires_separate_record_confirmation")),
        "actions": [],
    }

    bundle = find_bundle(token, target["bundle_id"])
    if bundle:
        bundle_id = bundle["id"]
        result["bundleResourceId"] = bundle_id
        result["bundleExists"] = True
    else:
        result["bundleExists"] = False
        result["actions"].append(f"create bundle ID {target['bundle_id']} ({target['platform']})")
        if not apply:
            missing_capabilities = [item["capabilityType"] for item in required]
            for capability_type in missing_capabilities:
                result["actions"].append(f"enable capability {capability_type} after bundle creation")
            result["missingCapabilities"] = missing_capabilities
            return result
        bundle = create_bundle(token, target)
        bundle_id = bundle["id"]
        result["bundleResourceId"] = bundle_id
        result["bundleExists"] = True
        result["createdBundle"] = True

    capability_types = existing_capability_types(token, bundle_id)
    missing_capabilities = [
        item["capabilityType"] for item in required if item["capabilityType"] not in capability_types
    ]
    for capability_type in missing_capabilities:
        result["actions"].append(f"enable capability {capability_type}")
        if apply:
            enable_capability(token, bundle_id, capability_type)
    result["missingCapabilities"] = missing_capabilities
    if apply:
        result["postApplyVerification"] = verify_target_state(token, name)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--target",
        action="append",
        choices=("all", *TARGETS.keys()),
        help="Target to plan/apply. Repeat for multiple targets. Defaults to all.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Create missing bundle IDs and enable required capabilities. Without this flag, only prints a plan.",
    )
    parser.add_argument(
        "--confirm-team",
        help=f"Required with --apply. Must match {TEAM_ID}, verified against {IOS_BUNDLE_ID}.",
    )
    parser.add_argument(
        "--confirm-separate-platform-records",
        action="store_true",
        help=(
            "Required with --apply for macOS or tvOS targets while those targets use separate "
            "bundle IDs instead of the iOS bundle ID used by a single App Store record/universal purchase."
        ),
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable output")
    args = parser.parse_args()

    token = build_token()
    team_context = None
    names = target_names(args.target or ["all"])
    if args.apply:
        if not args.confirm_team:
            fail(f"--apply requires --confirm-team {TEAM_ID}")
        separate_record_targets = targets_requiring_separate_record_confirmation(names)
        if separate_record_targets and not args.confirm_separate_platform_records:
            labels = ", ".join(TARGETS[name]["label"] for name in separate_record_targets)
            fail(
                "macOS/tvOS App Store platform versions normally share the iOS app's bundle ID "
                "when using a single App Store record/universal purchase. "
                f"Refusing to create separate bundle IDs for {labels} without "
                "--confirm-separate-platform-records. Use --target watchos to create only the "
                "Watch companion bundle ID."
            )
        team_context = confirm_team_for_apply(token, args.confirm_team)
    results = [process_target(token, name, args.apply) for name in names]
    verification_failed = args.apply and any(
        not result.get("postApplyVerification", {}).get("verified", False) for result in results
    )

    if args.json:
        print(
            json.dumps(
                {
                    "apply": args.apply,
                    "confirmedTeam": team_context.get("attributes", {}).get("seedId") if team_context else None,
                    "results": results,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 1 if verification_failed else 0

    print("Captain's Log platform bundle ID provisioning plan")
    print(f"Mode: {'apply' if args.apply else 'dry-run'}")
    if team_context:
        print(f"Confirmed team: {team_context.get('attributes', {}).get('seedId')} via {IOS_BUNDLE_ID}")
    for result in results:
        print(f"\n{result['label']}: {result['bundleId']}")
        if TARGETS[result["target"]].get("requires_separate_record_confirmation"):
            print(
                "[review] this target currently uses a separate bundle ID; confirm this is "
                "intended before creating account state for it"
            )
        if result.get("bundleExists"):
            print(f"[ok] Developer Portal bundle ID exists: {result.get('bundleResourceId')}")
        else:
            print("[plan] Developer Portal bundle ID is missing")
        actions = result.get("actions", [])
        if actions:
            for action in actions:
                print(f"[{'done' if args.apply else 'plan'}] {action}")
        else:
            print("[ok] required bundle ID and capabilities are present")
        verification = result.get("postApplyVerification")
        if verification:
            if verification.get("verified"):
                print(
                    "[ok] post-apply verification passed: "
                    f"{verification.get('bundleResourceId')} with required capabilities"
                )
            else:
                reason = verification.get("reason", "unknown verification failure")
                print(f"[fail] post-apply verification failed: {reason}")
    if not args.apply:
        print(
            f"\nDry run only. For Watch, re-run with --target watchos --apply --confirm-team {TEAM_ID} "
            "after explicit approval to mutate Apple Developer/App Store Connect state. "
            "For Mac/TV separate bundle IDs, also pass --confirm-separate-platform-records "
            "only after choosing that distribution model."
        )
    return 1 if verification_failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (EnsureError, asc.CheckError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
