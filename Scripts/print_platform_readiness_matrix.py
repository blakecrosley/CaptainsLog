#!/usr/bin/env python3
"""Print the current no-mutation platform readiness verdict."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[1]
IOS_BUNDLE_ID = "com.blakecrosley.captainslog"
WATCH_BUNDLE_ID = "com.blakecrosley.captainslog.watchkitapp"
DEFAULT_IPA = Path("/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa")
DEFAULT_EXPORT_MANIFEST = Path("/tmp/captainslog-current-appstore-export/Export/ExportManifest.txt")
DEFAULT_MAC_EXPORT = Path("/tmp/captainslog-current-macos-appstore-export/Export")
DEFAULT_WATCHOS_EXPORT = Path("/tmp/captainslog-current-watchos-appstore-export/Export")
DEFAULT_TVOS_EXPORT = Path("/tmp/captainslog-current-tvos-appstore-export/Export")
PLATFORM_KEYS = ("ipad", "vision", "mac", "watch", "tv")


def run_json(command: list[str]) -> tuple[dict[str, Any], str]:
    result = subprocess.run(command, cwd=ROOT_DIR, capture_output=True, text=True, check=False)
    output = result.stdout.strip()
    if not output:
        return {}, result.stderr.strip()
    try:
        return json.loads(output), result.stderr.strip()
    except json.JSONDecodeError as exc:
        return {}, f"Could not parse JSON from {' '.join(command)}: {exc}"


def path_exists(path: Path) -> bool:
    return path.exists()


def text_contains(path: Path, needle: str) -> bool:
    if not path.is_file():
        return False
    return needle in path.read_text(encoding="utf-8", errors="replace")


def launch_log_has_pid(path: Path, bundle_id: str) -> bool:
    if not path.is_file():
        return False
    prefix = f"{bundle_id}: "
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(prefix) and line[len(prefix) :].strip().isdigit():
            return True
    return False


def smoke_ok(smoke_dir: Path, launch_name: str, summary_name: str, bundle_id: str) -> bool:
    return (
        text_contains(smoke_dir / summary_name, "screenshot=skipped")
        and launch_log_has_pid(smoke_dir / launch_name, bundle_id)
    )


def target_blockers(remote: dict[str, Any], target: str) -> list[str]:
    target_status = remote.get("targets", {}).get(target, {})
    blockers: list[str] = []
    if target_status.get("bundleExists") is False:
        blockers.append(f"missing bundle ID {target_status.get('bundleId', target)}")
    for group in target_status.get("missingRequiredCertificateGroups", []):
        blockers.append(f"missing certificate group {group}")
    for profile_type in target_status.get("missingRequiredProfileTypes", []):
        blockers.append(f"missing profile {profile_type}")
    if target_status.get("profileRequirementVerified") is False and target == "watchos":
        blockers.append("signed Watch export/TestFlight not proven")
    return blockers


def platform_entry(
    key: str,
    platform: str,
    local_ok: bool,
    missing_local: str,
    blockers: list[str],
) -> dict[str, Any]:
    deduped_blockers = list(dict.fromkeys(blockers))
    return {
        "key": key,
        "platform": platform,
        "local_status": "local proof present" if local_ok else missing_local,
        "store_status": "blocked" if deduped_blockers else "ready",
        "blockers": deduped_blockers,
    }


def build_matrix(args: argparse.Namespace) -> dict[str, Any]:
    app_record, app_record_error = run_json(["Scripts/check_app_store_connect_record.py", "--json"])
    remote, remote_error = run_json(["Scripts/check_remote_signing_assets.py", "--json"])

    app_record_exists = app_record.get("appRecordCount", 0) > 0 and app_record.get("appRecordMetadataMatches") is True
    ipa_exists = path_exists(args.ipa)
    export_manifest_exists = path_exists(args.export_manifest)
    ios_distribution_ready = not target_blockers(remote, "ios")
    tvos_distribution_ready = not target_blockers(remote, "tvos")
    macos_distribution_ready = not target_blockers(remote, "macos")
    watch_distribution_ready = not target_blockers(remote, "watchos")
    mac_package_exists = any(args.macos_export.glob("*.pkg")) and path_exists(args.macos_export / "MacExportManifest.txt")
    watch_ipa_exists = any(args.watchos_export.glob("*.ipa")) and path_exists(
        args.watchos_export / "WatchExportManifest.txt"
    )
    tv_ipa_exists = any(args.tvos_export.glob("*.ipa")) and path_exists(args.tvos_export / "TvOSExportManifest.txt")

    ipad_smoke_dir = args.ipad_smoke
    vision_smoke_dir = args.vision_smoke
    macos_smoke_dir = args.macos_smoke
    watchos_smoke_dir = args.watchos_smoke
    tvos_smoke_dir = args.tvos_smoke

    ipad_local = (
        smoke_ok(ipad_smoke_dir, "ipad-launch.log", "ipad-launch-summary.txt", IOS_BUNDLE_ID)
        and text_contains(ipad_smoke_dir / "ipad-bundle-metadata.txt", "UIDeviceFamily: [1,2]")
    )
    vision_local = smoke_ok(
        vision_smoke_dir,
        "vision-compatible-launch.log",
        "vision-compatible-launch-summary.txt",
        IOS_BUNDLE_ID,
    )
    macos_launch_log = macos_smoke_dir / "macos-launch.log"
    macos_local = (
        macos_launch_log.is_file()
        and macos_launch_log.read_text(encoding="utf-8", errors="replace").strip().isdigit()
    )
    watchos_local = smoke_ok(
        watchos_smoke_dir,
        "watchos-launch.log",
        "watchos-launch-summary.txt",
        WATCH_BUNDLE_ID,
    )
    tvos_local = smoke_ok(
        tvos_smoke_dir,
        "tvos-launch.log",
        "tvos-launch-summary.txt",
        IOS_BUNDLE_ID,
    )

    platforms = [
        platform_entry(
            "ipad",
            "iPad",
            ipad_local,
            "missing local iPad smoke proof",
            [
                *([] if app_record_exists else ["App Store Connect app record missing"]),
                *([] if ios_distribution_ready else target_blockers(remote, "ios")),
                *([] if ipa_exists else [f"missing IPA {args.ipa}"]),
                *([] if export_manifest_exists else [f"missing export manifest {args.export_manifest}"]),
                "TestFlight/upload and final tap-through not proven",
            ],
        ),
        platform_entry(
            "vision",
            "Apple Vision Pro compatible",
            vision_local,
            "missing compatible Vision smoke proof",
            [
                *([] if app_record_exists else ["App Store Connect app record missing"]),
                *([] if ios_distribution_ready else target_blockers(remote, "ios")),
                *([] if ipa_exists else [f"missing IPA {args.ipa}"]),
                *([] if export_manifest_exists else [f"missing export manifest {args.export_manifest}"]),
                "signed TestFlight/auth/visual UX acceptance not proven",
            ],
        ),
        platform_entry(
            "mac",
            "Mac",
            macos_local,
            "missing local Mac launch proof",
            [
                *([] if app_record_exists else ["App Store Connect app record missing"]),
                *([] if macos_distribution_ready else target_blockers(remote, "macos")),
                *([] if mac_package_exists else [f"missing Mac App Store package or manifest under {args.macos_export}"]),
                "Mac TestFlight/store-media/human QA not proven",
            ],
        ),
        platform_entry(
            "watch",
            "Apple Watch",
            watchos_local,
            "missing local Watch launch proof",
            [
                *([] if app_record_exists else ["App Store Connect app record missing"]),
                *([] if watch_distribution_ready else target_blockers(remote, "watchos")),
                *([] if watch_ipa_exists else [f"missing Watch App Store IPA or manifest under {args.watchos_export}"]),
                "paired-device QA, store media, and TestFlight not proven",
            ],
        ),
        platform_entry(
            "tv",
            "Apple TV",
            tvos_local,
            "missing local TV launch proof",
            [
                *([] if app_record_exists else ["App Store Connect app record missing"]),
                *([] if tvos_distribution_ready else target_blockers(remote, "tvos")),
                *([] if tv_ipa_exists else [f"missing TV App Store IPA or manifest under {args.tvos_export}"]),
                "signed export, TestFlight, living-room QA, and store media not proven",
            ],
        ),
    ]

    return {
        "app_record_check_error": app_record_error,
        "remote_signing_check_error": remote_error,
        "app_record_exists": app_record_exists,
        "ipa_exists": ipa_exists,
        "export_manifest_exists": export_manifest_exists,
        "platforms": platforms,
    }


def print_markdown(matrix: dict[str, Any]) -> None:
    print("# Captain's Log Platform Readiness Matrix")
    print()
    print("This is a read-only verdict. It does not mutate Apple Developer or App Store Connect state.")
    print()
    print("| Platform | Local proof | Store readiness | Primary blockers |")
    print("| --- | --- | --- | --- |")
    for platform in matrix["platforms"]:
        blockers = "; ".join(dict.fromkeys(platform["blockers"]))
        print(
            f"| {platform['platform']} | {platform['local_status']} | "
            f"{platform['store_status']} | {blockers} |"
        )


def selected_platform_keys(selected: list[str] | None) -> set[str]:
    if not selected or "all" in selected:
        return set(PLATFORM_KEYS)
    return set(selected)


def filtered_matrix(matrix: dict[str, Any], platforms: set[str]) -> dict[str, Any]:
    if platforms == set(PLATFORM_KEYS):
        return matrix
    filtered = dict(matrix)
    filtered["platforms"] = [platform for platform in matrix["platforms"] if platform["key"] in platforms]
    return filtered


def check_matrix(
    matrix: dict[str, Any],
    require_local: bool,
    require_store: bool,
    platforms: set[str],
) -> list[str]:
    failures: list[str] = []
    if require_local:
        for platform in matrix["platforms"]:
            if platform["key"] not in platforms:
                continue
            if platform["local_status"] != "local proof present":
                failures.append(f"{platform['platform']}: {platform['local_status']}")
    if require_store:
        for platform in matrix["platforms"]:
            if platform["key"] not in platforms:
                continue
            if platform["store_status"] != "ready":
                blockers = "; ".join(platform["blockers"])
                failures.append(f"{platform['platform']}: store readiness blocked by {blockers}")
    return failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    parser.add_argument(
        "--platform",
        action="append",
        choices=("all", *PLATFORM_KEYS),
        help=(
            "Restrict output and --require-local/--require-store checks to selected platform key. "
            "Repeat for multiple platforms. Defaults to all."
        ),
    )
    parser.add_argument(
        "--require-local",
        action="store_true",
        help="Exit nonzero unless every platform has local no-screenshot proof",
    )
    parser.add_argument(
        "--require-store",
        action="store_true",
        help="Exit nonzero unless every platform is store-ready",
    )
    parser.add_argument("--ipa", type=Path, default=DEFAULT_IPA)
    parser.add_argument("--export-manifest", type=Path, default=DEFAULT_EXPORT_MANIFEST)
    parser.add_argument("--macos-export", type=Path, default=DEFAULT_MAC_EXPORT)
    parser.add_argument("--watchos-export", type=Path, default=DEFAULT_WATCHOS_EXPORT)
    parser.add_argument("--tvos-export", type=Path, default=DEFAULT_TVOS_EXPORT)
    parser.add_argument("--ipad-smoke", type=Path, default=Path("/tmp/captainslog-ipad-smoke"))
    parser.add_argument("--vision-smoke", type=Path, default=Path("/tmp/captainslog-vision-smoke"))
    parser.add_argument("--macos-smoke", type=Path, default=Path("/tmp/captainslog-macos-smoke"))
    parser.add_argument("--watchos-smoke", type=Path, default=Path("/tmp/captainslog-watchos-smoke"))
    parser.add_argument("--tvos-smoke", type=Path, default=Path("/tmp/captainslog-tvos-smoke"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selected_platforms = selected_platform_keys(args.platform)
    matrix = build_matrix(args)
    output_matrix = filtered_matrix(matrix, selected_platforms)
    if args.json:
        print(json.dumps(output_matrix, indent=2, sort_keys=True))
    else:
        print_markdown(output_matrix)
    failures = check_matrix(
        matrix,
        args.require_local,
        args.require_store,
        selected_platforms,
    )
    if failures:
        for failure in failures:
            print(f"[fail] {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
