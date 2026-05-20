#!/usr/bin/env python3
"""Plan or create App Store provisioning profiles for Captain's Log targets."""

from __future__ import annotations

import argparse
import base64
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.dont_write_bytecode = True

import check_app_store_connect_record as asc  # noqa: E402
import check_remote_signing_assets as remote  # noqa: E402


TEAM_ID = "M4WTLM6RAQ"
DEFAULT_PROFILE_DIR = Path.home() / "Library" / "Developer" / "Xcode" / "UserData" / "Provisioning Profiles"

TARGETS = {
    "ios": {
        "label": "iOS App Store",
        "bundle_id": "com.blakecrosley.captainslog",
        "profile_type": "IOS_APP_STORE",
        "certificate_group": "ios_distribution",
        "name": "Captain's Log iOS App Store",
        "extension": ".mobileprovision",
    },
    "macos": {
        "label": "native Mac App Store",
        "bundle_id": "com.blakecrosley.captainslog",
        "profile_type": "MAC_APP_STORE",
        "certificate_group": "mac_app_distribution",
        "name": "Captain's Log Mac App Store",
        "extension": ".provisionprofile",
    },
    "tvos": {
        "label": "Apple TV App Store",
        "bundle_id": "com.blakecrosley.captainslog",
        "profile_type": "TVOS_APP_STORE",
        "certificate_group": "ios_distribution",
        "name": "Captain's Log TV App Store",
        "extension": ".mobileprovision",
    },
}


class EnsureProfileError(Exception):
    pass


def fail(message: str) -> None:
    raise EnsureProfileError(message)


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


def target_names(selected: list[str] | None) -> list[str]:
    if not selected or "all" in selected:
        return list(TARGETS)
    unknown = sorted(set(selected) - set(TARGETS))
    if unknown:
        fail(f"Unknown target(s): {', '.join(unknown)}")
    return selected


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
            "fields[profiles]": "name,platform,profileType,profileState,createdDate,expirationDate,profileContent",
            "limit": "200",
        },
    )
    return payload.get("data", [])


def profile_summary(profile: dict[str, Any]) -> dict[str, Any]:
    attributes = profile.get("attributes", {})
    return {
        "id": profile.get("id"),
        "name": attributes.get("name"),
        "profileType": attributes.get("profileType"),
        "profileState": attributes.get("profileState"),
        "createdDate": attributes.get("createdDate"),
        "expirationDate": attributes.get("expirationDate"),
        "usable": attributes.get("profileState") == "ACTIVE" and remote.not_expired(attributes.get("expirationDate")),
    }


def fetch_certificates_for_group(token: str, group_name: str) -> list[dict[str, Any]]:
    group = remote.CERTIFICATE_GROUPS[group_name]
    certificates: list[dict[str, Any]] = []
    for certificate_type in group["types"]:
        payload = asc.api_get(
            token,
            "/v1/certificates",
            {
                "filter[certificateType]": certificate_type,
                "fields[certificates]": "certificateType,displayName,platform,expirationDate,activated",
                "limit": "200",
            },
        )
        certificates.extend(payload.get("data", []))
    return certificates


def certificate_summary(certificate: dict[str, Any]) -> dict[str, Any]:
    attributes = certificate.get("attributes", {})
    return {
        "id": certificate.get("id"),
        "displayName": attributes.get("displayName") or attributes.get("name"),
        "certificateType": attributes.get("certificateType"),
        "platform": attributes.get("platform"),
        "expirationDate": attributes.get("expirationDate"),
        "activated": attributes.get("activated"),
        "usable": attributes.get("activated") is not False and remote.not_expired(attributes.get("expirationDate")),
    }


def create_profile(
    token: str,
    target: dict[str, Any],
    bundle_resource_id: str,
    certificate_ids: list[str],
) -> dict[str, Any]:
    payload = {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": target["name"],
                "profileType": target["profile_type"],
            },
            "relationships": {
                "bundleId": {
                    "data": {
                        "type": "bundleIds",
                        "id": bundle_resource_id,
                    }
                },
                "certificates": {
                    "data": [{"type": "certificates", "id": certificate_id} for certificate_id in certificate_ids]
                },
            },
        }
    }
    return api_post(token, "/v1/profiles", payload)["data"]


def read_profile(token: str, profile_id: str) -> dict[str, Any]:
    return asc.api_get(
        token,
        f"/v1/profiles/{profile_id}",
        {"fields[profiles]": "name,profileType,profileState,expirationDate,profileContent"},
    ).get("data", {})


def safe_filename(text: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", text).strip("-")
    return cleaned or "profile"


def write_profile_content(profile: dict[str, Any], target: dict[str, Any], output_dir: Path) -> Path | None:
    attributes = profile.get("attributes", {})
    content = attributes.get("profileContent")
    if not content:
        return None
    output_dir.mkdir(parents=True, exist_ok=True)
    raw = base64.b64decode(content)
    name = safe_filename(attributes.get("name") or target["name"])
    profile_id = safe_filename(profile.get("id") or "created")
    output_path = output_dir / f"{name}-{profile_id}{target['extension']}"
    output_path.write_bytes(raw)
    return output_path


def process_target(
    token: str,
    name: str,
    apply: bool,
    download_existing: bool,
    download_dir: Path,
) -> dict[str, Any]:
    target = TARGETS[name]
    result: dict[str, Any] = {
        "target": name,
        "label": target["label"],
        "bundleId": target["bundle_id"],
        "profileType": target["profile_type"],
        "certificateGroup": target["certificate_group"],
        "actions": [],
    }

    bundle = find_bundle(token, target["bundle_id"])
    if not bundle:
        result["bundleExists"] = False
        result["actions"].append(f"create or make visible bundle ID {target['bundle_id']}")
        return result

    bundle_id = bundle["id"]
    result["bundleExists"] = True
    result["bundleResourceId"] = bundle_id
    result["bundleSeedId"] = bundle.get("attributes", {}).get("seedId")

    certificates = [certificate_summary(item) for item in fetch_certificates_for_group(token, target["certificate_group"])]
    usable_certificates = [item for item in certificates if item["usable"] and item.get("id")]
    result["usableCertificateCount"] = len(usable_certificates)
    result["certificates"] = certificates
    if not usable_certificates:
        label = remote.CERTIFICATE_GROUPS[target["certificate_group"]]["label"]
        result["actions"].append(f"create or make visible usable certificate group: {label}")
        return result

    profiles = [profile_summary(item) for item in fetch_profiles_for_bundle(token, bundle_id)]
    matching_profiles = [item for item in profiles if item.get("profileType") == target["profile_type"]]
    usable_profiles = [item for item in matching_profiles if item["usable"]]
    result["matchingProfiles"] = matching_profiles
    result["usableProfileCount"] = len(usable_profiles)
    if usable_profiles:
        if download_existing:
            downloaded: list[str] = []
            for usable_profile in usable_profiles:
                profile = read_profile(token, str(usable_profile["id"]))
                output_path = write_profile_content(profile, target, download_dir)
                if output_path:
                    downloaded.append(str(output_path))
            if downloaded:
                result["downloadedProfiles"] = downloaded
            else:
                result["actions"].append("download active profile from App Store Connect; profileContent was not returned")
        return result

    result["actions"].append(f"create {target['profile_type']} profile for {target['bundle_id']}")
    if not apply:
        return result

    profile = create_profile(
        token,
        target,
        bundle_id,
        [str(item["id"]) for item in usable_certificates],
    )
    profile = read_profile(token, profile["id"])
    result["createdProfile"] = profile_summary(profile)
    output_path = write_profile_content(profile, target, download_dir)
    if output_path:
        result["downloadedProfile"] = str(output_path)
    else:
        result["actions"].append("download created profile from App Store Connect; profileContent was not returned")
    return result


def confirm_team_for_apply(token: str, confirm_team: str) -> dict[str, Any]:
    if confirm_team != TEAM_ID:
        fail(f"--confirm-team must be {TEAM_ID} before --apply can mutate Apple account state")
    bundle = find_bundle(token, "com.blakecrosley.captainslog")
    if not bundle:
        fail("Cannot confirm team context because com.blakecrosley.captainslog is missing or not visible")
    seed_id = bundle.get("attributes", {}).get("seedId")
    if seed_id != TEAM_ID:
        fail(f"Expected com.blakecrosley.captainslog seedId {TEAM_ID}, got {seed_id or 'unknown'}")
    return bundle


def has_open_actions(results: list[dict[str, Any]]) -> bool:
    return any(result.get("actions") for result in results)


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
        help="Create missing App Store profiles and download returned profile content. Without this flag, only prints a plan.",
    )
    parser.add_argument(
        "--download-existing",
        action="store_true",
        help="Download active existing matching profiles to the local Xcode provisioning profile directory without creating profiles.",
    )
    parser.add_argument(
        "--confirm-team",
        help=f"Required with --apply. Must match {TEAM_ID}, verified against com.blakecrosley.captainslog.",
    )
    parser.add_argument("--download-dir", type=Path, default=DEFAULT_PROFILE_DIR)
    parser.add_argument("--json", action="store_true", help="Print machine-readable output")
    parser.add_argument(
        "--require-ready",
        action="store_true",
        help="Exit nonzero when selected targets still need profile/certificate actions.",
    )
    args = parser.parse_args()

    token = build_token()
    selected = target_names(args.target)
    team_context = None
    if args.apply:
        if not args.confirm_team:
            fail(f"--apply requires --confirm-team {TEAM_ID}")
        team_context = confirm_team_for_apply(token, args.confirm_team)

    results = [
        process_target(token, name, args.apply, args.download_existing, args.download_dir.expanduser())
        for name in selected
    ]

    if args.json:
        print(
            json.dumps(
                {
                    "apply": args.apply,
                    "confirmedTeam": team_context.get("attributes", {}).get("seedId") if team_context else None,
                    "downloadExisting": args.download_existing,
                    "downloadDir": str(args.download_dir.expanduser()),
                    "results": results,
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        print("Captain's Log App Store provisioning profile plan")
        print(f"Mode: {'apply' if args.apply else 'dry-run'}")
        if args.download_existing:
            print("Existing active profile download: enabled")
        if team_context:
            print(f"Confirmed team: {team_context.get('attributes', {}).get('seedId')}")
        print(f"Download directory: {args.download_dir.expanduser()}")
        for result in results:
            print(f"\n{result['label']}: {result['bundleId']} / {result['profileType']}")
            if result.get("bundleExists"):
                print(f"[ok] Developer Portal bundle ID exists: {result.get('bundleResourceId')}")
            else:
                print("[plan] Developer Portal bundle ID is missing or not visible")
            if result.get("usableCertificateCount", 0) > 0:
                print(f"[ok] usable certificate count: {result['usableCertificateCount']}")
            matching = result.get("matchingProfiles", [])
            usable_profile_count = result.get("usableProfileCount", 0)
            if usable_profile_count > 0:
                print(f"[ok] usable {result['profileType']} profile count: {usable_profile_count}")
            elif matching:
                print(f"[warn] matching profile count: {len(matching)}, but none are active and usable")
            for profile in matching:
                marker = "ok" if profile["usable"] else "warn"
                print(
                    f"  [{marker}] {profile.get('profileType') or 'unknown'} "
                    f"{profile.get('name') or '(unnamed)'} "
                    f"state {profile.get('profileState') or 'unknown'} "
                    f"expires {profile.get('expirationDate') or 'unknown'}"
                )
            for action in result.get("actions", []):
                print(f"[{'done' if args.apply else 'plan'}] {action}")
            if result.get("createdProfile"):
                created = result["createdProfile"]
                print(
                    f"[done] created {created.get('profileType')} profile "
                    f"{created.get('name') or created.get('id')}"
                )
            if result.get("downloadedProfile"):
                print(f"[done] wrote profile: {result['downloadedProfile']}")
            for downloaded in result.get("downloadedProfiles", []):
                print(f"[done] wrote existing profile: {downloaded}")
            if not result.get("actions") and usable_profile_count == 0 and result.get("bundleExists"):
                print("[ok] no profile action required by this target")
        if not args.apply:
            print(
                f"\nDry run only. Re-run with --apply --confirm-team {TEAM_ID} "
                "only after explicit approval to mutate Apple Developer/App Store Connect profile state."
            )

    if args.require_ready and has_open_actions(results):
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (EnsureProfileError, asc.CheckError, remote.RemoteSigningError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
