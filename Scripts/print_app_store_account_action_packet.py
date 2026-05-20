#!/usr/bin/env python3
"""Print the next no-screenshot App Store account/signing action packet."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[1]
KIT941_DIR = ROOT_DIR.parent / "941Kit"


class PacketError(Exception):
    pass


def run_json(command: list[str]) -> dict[str, Any]:
    result = subprocess.run(command, cwd=ROOT_DIR, capture_output=True, text=True, check=False)
    output = result.stdout.strip()
    if not output:
        raise PacketError(f"{' '.join(command)} produced no JSON output: {result.stderr.strip()}")
    try:
        payload = json.loads(output)
    except json.JSONDecodeError as exc:
        raise PacketError(f"Could not parse JSON from {' '.join(command)}: {exc}") from exc
    payload["_command"] = command
    payload["_returncode"] = result.returncode
    payload["_stderr"] = result.stderr.strip()
    return payload


def run_text(command: list[str]) -> dict[str, Any]:
    result = subprocess.run(command, cwd=ROOT_DIR, capture_output=True, text=True, check=False)
    return {
        "_command": command,
        "_returncode": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }


def git_summary(repo: Path, label: str) -> dict[str, Any]:
    status_result = subprocess.run(
        ["git", "status", "--short", "--branch"],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
    )
    head_result = subprocess.run(
        ["git", "log", "-1", "--oneline"],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
    )
    status_lines = status_result.stdout.strip().splitlines()
    branch_line = status_lines[0] if status_lines else ""
    dirty_lines = status_lines[1:]
    upstream_synced = "[ahead" not in branch_line and "[behind" not in branch_line and "[gone]" not in branch_line
    return {
        "label": label,
        "path": str(repo),
        "branch_status": branch_line,
        "head": head_result.stdout.strip(),
        "clean": status_result.returncode == 0 and not dirty_lines,
        "upstream_synced": upstream_synced,
        "dirty_entries": dirty_lines,
        "status_returncode": status_result.returncode,
    }


def profile_actions(profile_plan: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    for result in profile_plan.get("results", []):
        for action in result.get("actions", []):
            actions.append(
                {
                    "target": result.get("target"),
                    "label": result.get("label"),
                    "bundle_id": result.get("bundleId"),
                    "profile_type": result.get("profileType"),
                    "action": action,
                }
            )
    return actions


def bundle_actions(bundle_plan: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    for result in bundle_plan.get("results", []):
        for action in result.get("actions", []):
            actions.append(
                {
                    "target": result.get("target"),
                    "label": result.get("label"),
                    "bundle_id": result.get("bundleId"),
                    "action": action,
                }
            )
    return actions


def missing_certificate_actions(remote: dict[str, Any]) -> list[str]:
    actions: list[str] = []
    certificates = remote.get("certificates", {})
    mac_installer = certificates.get("mac_installer_distribution", {})
    if mac_installer.get("usableCertificateCount", 0) == 0:
        actions.append("Create or make visible a Mac App Store installer distribution certificate.")
    return actions


def platform_rows(matrix: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "platform": item.get("platform"),
            "local_status": item.get("local_status"),
            "store_status": item.get("store_status"),
            "blockers": item.get("blockers", []),
        }
        for item in matrix.get("platforms", [])
    ]


def build_packet() -> dict[str, Any]:
    app_record = run_json(["Scripts/check_app_store_connect_record.py", "--json"])
    remote = run_json(["Scripts/check_remote_signing_assets.py", "--json"])
    bundle_plan = run_json(["Scripts/ensure_platform_bundle_ids.py", "--json"])
    profile_plan = run_json(["Scripts/ensure_app_store_profiles.py", "--json"])
    matrix = run_json(["Scripts/print_platform_readiness_matrix.py", "--json"])
    entry_check = run_text(["Scripts/print_app_store_entry_packet.py", "--check"])
    held_marketing_check = run_text(["Scripts/print_held_platform_marketing_packet.py", "--check"])

    app_record_exists = (
        app_record.get("appRecordCount", 0) > 0 and app_record.get("appRecordMetadataMatches") is True
    )
    return {
        "app_record": {
            "exists": app_record_exists,
            "bundle_id": app_record.get("bundleId"),
            "bundle_id_exists": app_record.get("bundleIdRecordCount", 0) > 0,
            "required_capabilities_missing": app_record.get("missingRequiredCapabilities", []),
            "lookup_method": app_record.get("appRecordLookupMethod"),
            "expected_sku": app_record.get("expectedSku"),
            "expected_sku_matches": app_record.get("expectedSkuAppRecordCount", 0),
            "expected_name": app_record.get("expectedAppName"),
            "expected_name_matches": app_record.get("expectedNameAppRecordCount", 0),
        },
        "entry_packet_valid": entry_check["_returncode"] == 0,
        "held_platform_marketing_valid": held_marketing_check["_returncode"] == 0,
        "source_custody": [
            git_summary(ROOT_DIR, "CaptainsLog"),
            git_summary(KIT941_DIR, "Kit941"),
        ],
        "bundle_actions": bundle_actions(bundle_plan),
        "profile_actions": profile_actions(profile_plan),
        "certificate_actions": missing_certificate_actions(remote),
        "platforms": platform_rows(matrix),
        "commands": {
            "read_only": [
                "git status --short --branch",
                "git -C ../941Kit status --short --branch",
                "Scripts/print_app_store_entry_packet.py --check",
                "Scripts/print_held_platform_marketing_packet.py --check",
                "Scripts/check_app_store_connect_record.py",
                "Scripts/check_remote_signing_assets.py --require",
                "Scripts/ensure_platform_bundle_ids.py",
                "Scripts/ensure_app_store_profiles.py",
                "Scripts/print_platform_readiness_matrix.py --require-local",
            ],
            "mutating_after_approval": [
                "Scripts/ensure_platform_bundle_ids.py --target watchos --apply --confirm-team M4WTLM6RAQ",
                "Scripts/ensure_app_store_profiles.py --target ios --apply --confirm-team M4WTLM6RAQ",
                "Scripts/ensure_app_store_profiles.py --target macos --apply --confirm-team M4WTLM6RAQ",
                "Scripts/ensure_app_store_profiles.py --target tvos --apply --confirm-team M4WTLM6RAQ",
            ],
            "source_sync_after_approval": [
                "git push",
                "git -C ../941Kit push",
            ],
            "exports_after_signing": [
                "CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export",
                "CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export",
                "CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_watchos_app_store_ipa.sh /tmp/captainslog-current-watchos-appstore-export",
                "CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_tvos_app_store_ipa.sh /tmp/captainslog-current-tvos-appstore-export",
            ],
        },
    }


def print_markdown(packet: dict[str, Any]) -> None:
    print("# Captain's Log App Store Account Action Packet")
    print()
    print("Read-only packet. It does not create bundle IDs, profiles, app records, exports, or screenshots.")
    print()

    print("## Source Custody")
    print()
    for source in packet["source_custody"]:
        status = "clean" if source["clean"] else "dirty"
        sync = "synced" if source["upstream_synced"] else "not synced"
        print(f"- {source['label']}: {status}, {sync}; `{source['branch_status']}`; HEAD `{source['head']}`.")
        if source["dirty_entries"]:
            dirty = "; ".join(source["dirty_entries"])
            print(f"  Dirty entries: {dirty}")
    if any(not source["upstream_synced"] for source in packet["source_custody"]):
        print("- Before final signed export, push these save points or explicitly accept the unpushed source state.")
    print()

    app_record = packet["app_record"]
    print("## Web UI First")
    print()
    if app_record["exists"]:
        print(f"- App Store Connect app record is visible for `{app_record['bundle_id']}`.")
    else:
        print(
            "- Create or make visible the App Store Connect app record: "
            f"`{app_record['expected_name']}` / SKU `{app_record['expected_sku']}` / "
            f"bundle `{app_record['bundle_id']}`."
        )
        print(
            f"- Current read-only lookup: `{app_record['lookup_method']}`, "
            f"SKU matches `{app_record['expected_sku_matches']}`, "
            f"name matches `{app_record['expected_name_matches']}`."
        )
    if app_record["required_capabilities_missing"]:
        missing = ", ".join(app_record["required_capabilities_missing"])
        print(f"- Enable missing bundle capability/capabilities: {missing}.")
    elif app_record["bundle_id_exists"]:
        print("- Developer Portal iOS bundle ID is visible and required iCloud capability is present.")
    if packet["entry_packet_valid"]:
        print("- First-release App Store Connect entry packet validates.")
    if packet["held_platform_marketing_valid"]:
        print("- Held native Mac, Watch, and TV marketing packet validates; keep it held until the matching platform gates close.")
    print()

    print("## Bundle IDs And Profiles")
    print()
    bundle_actions_value = packet["bundle_actions"]
    profile_actions_value = packet["profile_actions"]
    certificate_actions_value = packet["certificate_actions"]
    if not bundle_actions_value and not profile_actions_value and not certificate_actions_value:
        print("- No bundle/profile/certificate actions are currently planned by the read-only helpers.")
    for action in certificate_actions_value:
        print(f"- {action}")
    for action in bundle_actions_value:
        print(f"- {action['label']}: {action['action']}")
    for action in profile_actions_value:
        print(f"- {action['label']}: {action['action']}")
    print()

    print("## Verification Commands")
    print()
    print("```sh")
    for command in packet["commands"]["read_only"]:
        print(command)
    print("```")
    print()

    print("## Mutating Commands")
    print()
    print("Run these only after explicit Apple account mutation approval and after the matching dry-run output is accepted.")
    print()
    print("```sh")
    for command in packet["commands"]["mutating_after_approval"]:
        print(command)
    print("```")
    print()

    print("## Source Sync Commands")
    print()
    print("Run only after explicit push/sync approval.")
    print()
    print("```sh")
    for command in packet["commands"]["source_sync_after_approval"]:
        print(command)
    print("```")
    print()

    print("## Export Commands")
    print()
    print("Run only after the app record, bundle IDs, certificates, and active profiles are ready.")
    print()
    print("```sh")
    for command in packet["commands"]["exports_after_signing"]:
        print(command)
    print("```")
    print()

    print("## Platform Store Verdict")
    print()
    print("| Platform | Local proof | Store status | Blockers |")
    print("| --- | --- | --- | --- |")
    for platform in packet["platforms"]:
        blockers = "; ".join(platform["blockers"])
        print(
            f"| {platform['platform']} | {platform['local_status']} | "
            f"{platform['store_status']} | {blockers} |"
        )


def validate_packet(packet: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if not packet.get("entry_packet_valid"):
        errors.append("App Store entry packet validation failed")
    if not packet.get("held_platform_marketing_valid"):
        errors.append("Held platform marketing packet validation failed")
    if not packet.get("platforms"):
        errors.append("Platform readiness matrix is empty")
    if not packet.get("commands", {}).get("read_only"):
        errors.append("Read-only verification commands are missing")
    if not packet.get("source_custody"):
        errors.append("Source custody section is missing")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Print machine-readable output")
    parser.add_argument("--check", action="store_true", help="Validate packet generation only")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        packet = build_packet()
    except PacketError as exc:
        print(f"[fail] {exc}", file=sys.stderr)
        return 1

    errors = validate_packet(packet)
    if errors:
        for error in errors:
            print(f"[fail] {error}", file=sys.stderr)
        return 1
    if args.check:
        print("[ok] App Store account action packet is valid")
        return 0
    if args.json:
        print(json.dumps(packet, indent=2, sort_keys=True))
    else:
        print_markdown(packet)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
