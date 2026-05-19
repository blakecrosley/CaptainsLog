#!/usr/bin/env python3
"""Read-only App Store Connect certificate/profile inventory for Captain's Log."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.dont_write_bytecode = True

import check_app_store_connect_record as asc  # noqa: E402


TEAM_ID = "M4WTLM6RAQ"
TARGETS = {
    "ios": {
        "label": "iOS",
        "bundle_id": "com.blakecrosley.captainslog",
        "required_profile_types": ["IOS_APP_STORE"],
        "required_certificate_groups": ["ios_distribution"],
    },
    "macos": {
        "label": "native Mac",
        "bundle_id": "com.blakecrosley.captainslog",
        "required_profile_types": ["MAC_APP_STORE"],
        "required_certificate_groups": ["mac_app_distribution", "mac_installer_distribution"],
    },
    "watchos": {
        "label": "Apple Watch",
        "bundle_id": "com.blakecrosley.captainslog.watchkitapp",
        "required_profile_types": [],
        "required_certificate_groups": ["ios_distribution"],
        "profile_requirement_verified": False,
        "profile_requirement_note": (
            "Apple's Profile API currently documents no dedicated watchOS App Store "
            "profileType value; signed export/TestFlight remains the release authority."
        ),
    },
    "tvos": {
        "label": "Apple TV",
        "bundle_id": "com.blakecrosley.captainslog",
        "required_profile_types": ["TVOS_APP_STORE"],
        "required_certificate_groups": ["ios_distribution"],
    },
}

CERTIFICATE_GROUPS = {
    "ios_distribution": {
        "label": "iOS App Store distribution",
        "types": ["IOS_DISTRIBUTION", "DISTRIBUTION"],
    },
    "mac_app_distribution": {
        "label": "Mac App Store application distribution",
        "types": ["MAC_APP_DISTRIBUTION", "DISTRIBUTION"],
    },
    "mac_installer_distribution": {
        "label": "Mac App Store installer distribution",
        "types": ["MAC_INSTALLER_DISTRIBUTION"],
    },
}


class RemoteSigningError(Exception):
    pass


def fail(message: str) -> None:
    raise RemoteSigningError(message)


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


def parse_apple_date(value: str | None) -> datetime | None:
    if not value:
        return None
    normalized = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None


def not_expired(value: str | None) -> bool:
    parsed = parse_apple_date(value)
    if parsed is None:
        return True
    return parsed > datetime.now(timezone.utc)


def fetch_certificates(token: str, certificate_type: str) -> list[dict[str, Any]]:
    payload = asc.api_get(
        token,
        "/v1/certificates",
        {
            "filter[certificateType]": certificate_type,
            "fields[certificates]": "certificateType,displayName,platform,expirationDate,activated",
            "limit": "200",
        },
    )
    return payload.get("data", [])


def summarize_certificate(certificate: dict[str, Any]) -> dict[str, Any]:
    attributes = certificate.get("attributes", {})
    return {
        "displayName": attributes.get("displayName") or attributes.get("name"),
        "certificateType": attributes.get("certificateType"),
        "platform": attributes.get("platform"),
        "expirationDate": attributes.get("expirationDate"),
        "activated": attributes.get("activated"),
        "usable": attributes.get("activated") is not False and not_expired(attributes.get("expirationDate")),
    }


def find_bundle(token: str, bundle_id: str) -> dict[str, Any] | None:
    payload = asc.api_get(
        token,
        "/v1/bundleIds",
        {"filter[identifier]": bundle_id, "fields[bundleIds]": "identifier,name,platform,seedId"},
    )
    matches = asc.exact_bundle_matches(payload.get("data", []), bundle_id)
    return matches[0] if matches else None


def fetch_profiles_for_bundle(token: str, bundle_resource_id: str) -> list[dict[str, Any]]:
    payload = asc.api_get(
        token,
        f"/v1/bundleIds/{bundle_resource_id}/profiles",
        {
            "fields[profiles]": "name,platform,profileType,profileState,createdDate,expirationDate",
            "limit": "200",
        },
    )
    return payload.get("data", [])


def summarize_profile(profile: dict[str, Any]) -> dict[str, Any]:
    attributes = profile.get("attributes", {})
    return {
        "name": attributes.get("name"),
        "platform": attributes.get("platform"),
        "profileType": attributes.get("profileType"),
        "profileState": attributes.get("profileState"),
        "createdDate": attributes.get("createdDate"),
        "expirationDate": attributes.get("expirationDate"),
        "usable": attributes.get("profileState") == "ACTIVE" and not_expired(attributes.get("expirationDate")),
    }


def collect_status(token: str, targets: list[str]) -> dict[str, Any]:
    certificate_results: dict[str, Any] = {}
    for key, group in CERTIFICATE_GROUPS.items():
        certificates: list[dict[str, Any]] = []
        for certificate_type in group["types"]:
            certificates.extend(summarize_certificate(item) for item in fetch_certificates(token, certificate_type))
        usable = [item for item in certificates if item["usable"]]
        certificate_results[key] = {
            "label": group["label"],
            "certificateTypes": group["types"],
            "certificateCount": len(certificates),
            "usableCertificateCount": len(usable),
            "certificates": certificates,
        }

    target_results: dict[str, Any] = {}
    for key in targets:
        target = TARGETS[key]
        bundle = find_bundle(token, target["bundle_id"])
        if not bundle:
            target_results[key] = {
                "label": target["label"],
                "bundleId": target["bundle_id"],
                "bundleExists": False,
                "requiredProfileTypes": target["required_profile_types"],
                "requiredCertificateGroups": target["required_certificate_groups"],
                "missingRequiredCertificateGroups": [
                    certificate_group
                    for certificate_group in target["required_certificate_groups"]
                    if certificate_results[certificate_group]["usableCertificateCount"] == 0
                ],
                "profileRequirementVerified": target.get("profile_requirement_verified", True),
                "profileRequirementNote": target.get("profile_requirement_note"),
                "profiles": [],
                "missingRequiredProfileTypes": target["required_profile_types"],
            }
            continue

        profiles = [summarize_profile(item) for item in fetch_profiles_for_bundle(token, bundle["id"])]
        usable_profile_types = {
            profile["profileType"]
            for profile in profiles
            if profile.get("profileType") and profile["usable"]
        }
        missing_required_profile_types = [
            profile_type
            for profile_type in target["required_profile_types"]
            if profile_type not in usable_profile_types
        ]
        missing_required_certificate_groups = [
            certificate_group
            for certificate_group in target["required_certificate_groups"]
            if certificate_results[certificate_group]["usableCertificateCount"] == 0
        ]
        target_results[key] = {
            "label": target["label"],
            "bundleId": target["bundle_id"],
            "bundleExists": True,
            "bundlePlatform": bundle.get("attributes", {}).get("platform"),
            "bundleSeedId": bundle.get("attributes", {}).get("seedId"),
            "requiredProfileTypes": target["required_profile_types"],
            "requiredCertificateGroups": target["required_certificate_groups"],
            "missingRequiredCertificateGroups": missing_required_certificate_groups,
            "profileRequirementVerified": target.get("profile_requirement_verified", True),
            "profileRequirementNote": target.get("profile_requirement_note"),
            "profileCount": len(profiles),
            "usableProfileTypes": sorted(usable_profile_types),
            "missingRequiredProfileTypes": missing_required_profile_types,
            "profiles": profiles,
        }

    return {
        "teamId": TEAM_ID,
        "certificates": certificate_results,
        "targets": target_results,
    }


def print_status(status: dict[str, Any]) -> None:
    print("Captain's Log remote signing assets")
    print(f"Team ID: {status['teamId']}")
    print()
    print("Remote certificates")
    for result in status["certificates"].values():
        prefix = "[ok]" if result["usableCertificateCount"] else "[warn]"
        print(
            f"{prefix} {result['label']}: "
            f"{result['usableCertificateCount']} usable / {result['certificateCount']} visible"
        )
        for certificate in result["certificates"]:
            marker = "ok" if certificate["usable"] else "warn"
            print(
                f"  [{marker}] {certificate.get('certificateType') or 'unknown'} "
                f"{certificate.get('displayName') or '(unnamed)'} "
                f"expires {certificate.get('expirationDate') or 'unknown'}"
            )

    print()
    print("Remote provisioning profiles by bundle ID")
    for result in status["targets"].values():
        if not result["bundleExists"]:
            print(f"[fail] {result['label']} bundle ID missing: {result['bundleId']}")
            missing_certificates = result["missingRequiredCertificateGroups"]
            if missing_certificates:
                labels = [status["certificates"][key]["label"] for key in missing_certificates]
                print(f"  [fail] missing required certificate group(s): {', '.join(labels)}")
            if not result.get("profileRequirementVerified", True):
                print(f"  [info] {result.get('profileRequirementNote')}")
            continue

        print(
            f"[ok] {result['label']} bundle ID exists: {result['bundleId']} "
            f"({result.get('bundlePlatform') or 'unknown'}, seed {result.get('bundleSeedId') or 'unknown'})"
        )
        missing_certificates = result["missingRequiredCertificateGroups"]
        if missing_certificates:
            labels = [status["certificates"][key]["label"] for key in missing_certificates]
            print(f"[fail] {result['label']} missing required certificate group(s): {', '.join(labels)}")
        else:
            labels = [status["certificates"][key]["label"] for key in result["requiredCertificateGroups"]]
            print(f"[ok] {result['label']} required certificate group(s) visible: {', '.join(labels)}")

        required = result["requiredProfileTypes"]
        if not result.get("profileRequirementVerified", True):
            print(f"[fail] {result['label']} profile requirement is not fully verified by this checker")
            print(f"  [info] {result.get('profileRequirementNote')}")
        elif required:
            if result["missingRequiredProfileTypes"]:
                print(
                    f"[fail] {result['label']} missing required profile type(s): "
                    f"{', '.join(result['missingRequiredProfileTypes'])}"
                )
            else:
                print(f"[ok] {result['label']} required profile type(s) visible: {', '.join(required)}")
        else:
            print(f"[info] {result['label']} has no required profile type asserted by this checker")

        for profile in result["profiles"]:
            marker = "ok" if profile["usable"] else "warn"
            print(
                f"  [{marker}] {profile.get('profileType') or 'unknown'} "
                f"{profile.get('name') or '(unnamed)'} "
                f"state {profile.get('profileState') or 'unknown'} "
                f"expires {profile.get('expirationDate') or 'unknown'}"
            )

    print()
    print("Note: visible remote certificates/profiles do not prove local private-key access or")
    print("cloud-managed distribution certificate permission. exportArchive remains the authority.")


def has_missing_required_assets(status: dict[str, Any], targets: list[str]) -> bool:
    for key in targets:
        result = status["targets"][key]
        if result["missingRequiredCertificateGroups"]:
            return True
        if not result["bundleExists"]:
            return True
        if not result.get("profileRequirementVerified", True):
            return True
        if result["missingRequiredProfileTypes"]:
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--target",
        choices=sorted(TARGETS),
        action="append",
        help="Limit profile checks to one target. Can be passed more than once.",
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable status")
    parser.add_argument(
        "--require",
        action="store_true",
        help="Exit nonzero when a selected target is missing its required remote assets.",
    )
    args = parser.parse_args()

    selected_targets = args.target or list(TARGETS)
    token = build_token()
    status = collect_status(token, selected_targets)

    if args.json:
        print(json.dumps(status, indent=2, sort_keys=True))
    else:
        print_status(status)

    if args.require and has_missing_required_assets(status, selected_targets):
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RemoteSigningError, asc.CheckError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
