#!/usr/bin/env python3
"""Print and validate the safe App Store Connect entry packet."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_METADATA_PATH = ROOT_DIR / "Docs" / "AppStoreMetadata.md"


@dataclass(frozen=True)
class FieldSpec:
    key: str
    label: str
    required: bool = True
    min_chars: int | None = None
    max_chars: int | None = None
    max_bytes: int | None = None
    expected: str | None = None
    must_start_with: str | None = None


FIELD_SPECS = [
    FieldSpec("name", "Name", min_chars=2, max_chars=30, expected="Captain's Log"),
    FieldSpec("subtitle", "Subtitle", max_chars=30),
    FieldSpec("primary_category", "Primary category", expected="Developer Tools"),
    FieldSpec("secondary_category", "Secondary category", expected="Productivity"),
    FieldSpec("sku", "SKU", expected="captainslog-ios"),
    FieldSpec("bundle_id", "Bundle ID", expected="com.blakecrosley.captainslog"),
    FieldSpec("privacy_policy_url", "Privacy Policy URL", must_start_with="https://"),
    FieldSpec("support_url", "Support URL", must_start_with="https://"),
    FieldSpec("copyright", "Copyright"),
    FieldSpec("age_rating_notes", "Age rating notes"),
    FieldSpec("export_compliance_note", "Export compliance note"),
    FieldSpec("promotional_text", "Promotional text", max_chars=170),
    FieldSpec("description", "Description", max_chars=4000),
    FieldSpec("keywords", "Keywords", max_bytes=100),
    FieldSpec("whats_new", "What's New", required=False),
    FieldSpec("app_review_notes", "App Review Notes", max_bytes=4000),
]

PRIVATE_MARKERS = (
    "APP_STORE_CONNECT_API_KEY",
    "APP_STORE_CONNECT_API_ISSUER",
    "APP_STORE_CONNECT_P8_FILE",
    "ASC_KEY_ID",
    "ASC_ISSUER_ID",
    "ASC_KEY_PATH",
    "AuthKey_",
    "BEGIN PRIVATE KEY",
    "<KEY",
    "<ISSUER",
    "<absolute/path",
)


class PacketError(Exception):
    pass


def extract_text_block(markdown: str, label: str) -> str:
    label_pattern = re.compile(
        rf"^{re.escape(label)}:\s*\n\s*```text\n(?P<value>.*?)\n```",
        re.MULTILINE | re.DOTALL,
    )
    match = label_pattern.search(markdown)
    if not match:
        heading_pattern = re.compile(
            rf"^##\s+{re.escape(label)}\s*\n\s*```text\n(?P<value>.*?)\n```",
            re.MULTILINE | re.DOTALL,
        )
        match = heading_pattern.search(markdown)
    if not match:
        raise PacketError(f"Could not find text block for '{label}'")
    return match.group("value")


def extract_manual_choices(markdown: str) -> list[dict[str, str]]:
    heading = "## Manual App Store Connect Choices"
    try:
        start = markdown.index(heading)
    except ValueError as exc:
        raise PacketError(f"Could not find '{heading}'") from exc

    following = markdown[start:]
    next_heading = re.search(r"^##\s+", following[len(heading) :], re.MULTILINE)
    table_text = following[: len(heading) + next_heading.start()] if next_heading else following
    choices: list[dict[str, str]] = []
    for line in table_text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|") or stripped.startswith("| ---"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) != 3 or cells[0] == "App Store Connect area":
            continue
        choices.append({"area": cells[0], "recommended_value": cells[1], "notes": cells[2]})
    if not choices:
        raise PacketError("Manual App Store Connect choices table is empty")
    return choices


def build_packet(metadata_path: Path) -> dict[str, Any]:
    markdown = metadata_path.read_text(encoding="utf-8")
    fields: dict[str, str] = {}
    for spec in FIELD_SPECS:
        try:
            fields[spec.key] = extract_text_block(markdown, spec.label).strip()
        except PacketError:
            if spec.required:
                raise
            fields[spec.key] = ""

    return {
        "source": str(metadata_path.relative_to(ROOT_DIR)),
        "app_information": {
            "name": fields["name"],
            "subtitle": fields["subtitle"],
            "primary_category": fields["primary_category"],
            "secondary_category": fields["secondary_category"],
            "sku": fields["sku"],
            "bundle_id": fields["bundle_id"],
            "privacy_policy_url": fields["privacy_policy_url"],
            "support_url": fields["support_url"],
            "copyright": fields["copyright"],
        },
        "version_information": {
            "promotional_text": fields["promotional_text"],
            "description": fields["description"],
            "keywords": fields["keywords"],
            "whats_new": fields["whats_new"],
            "app_review_notes": fields["app_review_notes"],
        },
        "manual_choices": extract_manual_choices(markdown),
        "review_helpers": {
            "age_rating_notes": fields["age_rating_notes"],
            "export_compliance_note": fields["export_compliance_note"],
        },
        "private_fields": [
            "App Review contact",
            "Demo GitHub review account credentials",
            "EU DSA trader contact details",
            "App Store Connect Apple ID after record creation",
            "API key ID, issuer ID, and .p8 private key path",
        ],
    }


def validate_packet(packet: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    all_values: dict[str, str] = {}
    all_values.update(packet["app_information"])
    all_values.update(packet["version_information"])
    all_values.update(packet["review_helpers"])

    for spec in FIELD_SPECS:
        value = all_values.get(spec.key, "")
        if spec.required and not value:
            errors.append(f"{spec.label} is empty")
        if spec.min_chars is not None and len(value) < spec.min_chars:
            errors.append(f"{spec.label} is {len(value)} characters, expected at least {spec.min_chars}")
        if spec.max_chars is not None and len(value) > spec.max_chars:
            errors.append(f"{spec.label} is {len(value)} characters, max {spec.max_chars}")
        if spec.max_bytes is not None and len(value.encode("utf-8")) > spec.max_bytes:
            errors.append(f"{spec.label} is {len(value.encode('utf-8'))} bytes, max {spec.max_bytes}")
        if spec.expected is not None and value != spec.expected:
            errors.append(f"{spec.label} is {value!r}, expected {spec.expected!r}")
        if spec.must_start_with is not None and not value.startswith(spec.must_start_with):
            errors.append(f"{spec.label} must start with {spec.must_start_with!r}")

    for key, value in all_values.items():
        for marker in PRIVATE_MARKERS:
            if marker in value:
                errors.append(f"{key} contains private/local marker {marker!r}")

    return errors


def print_markdown(packet: dict[str, Any]) -> None:
    print("# Captain's Log App Store Connect Entry Packet")
    print()
    print(f"Source: `{packet['source']}`")
    print()
    print("## App Information")
    print()
    for label, value in (
        ("Name", packet["app_information"]["name"]),
        ("Subtitle", packet["app_information"]["subtitle"]),
        ("Primary category", packet["app_information"]["primary_category"]),
        ("Secondary category", packet["app_information"]["secondary_category"]),
        ("SKU", packet["app_information"]["sku"]),
        ("Bundle ID", packet["app_information"]["bundle_id"]),
        ("Privacy Policy URL", packet["app_information"]["privacy_policy_url"]),
        ("Support URL", packet["app_information"]["support_url"]),
        ("Copyright", packet["app_information"]["copyright"]),
    ):
        print(f"{label}:")
        print()
        print("```text")
        print(value)
        print("```")
        print()

    print("## Version Information")
    print()
    for label, value in (
        ("Promotional text", packet["version_information"]["promotional_text"]),
        ("Description", packet["version_information"]["description"]),
        ("Keywords", packet["version_information"]["keywords"]),
        ("What's New / TestFlight notes", packet["version_information"]["whats_new"]),
        ("App Review notes", packet["version_information"]["app_review_notes"]),
    ):
        print(f"{label}:")
        print()
        print("```text")
        print(value)
        print("```")
        print()

    print("## Manual Choices")
    print()
    print("| Area | First value |")
    print("| --- | --- |")
    for choice in packet["manual_choices"]:
        print(f"| {choice['area']} | {choice['recommended_value']} |")
    print()

    print("## Review Helpers")
    print()
    for label, value in (
        ("Age rating notes", packet["review_helpers"]["age_rating_notes"]),
        ("Export compliance note", packet["review_helpers"]["export_compliance_note"]),
    ):
        print(f"{label}:")
        print()
        print("```text")
        print(value)
        print("```")
        print()

    print("Private fields to enter only inside App Store Connect:")
    for value in packet["private_fields"]:
        print(f"- {value}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--metadata",
        type=Path,
        default=DEFAULT_METADATA_PATH,
        help="Path to Docs/AppStoreMetadata.md",
    )
    parser.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    parser.add_argument("--check", action="store_true", help="Validate only")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    metadata_path = args.metadata.resolve()
    try:
        packet = build_packet(metadata_path)
        errors = validate_packet(packet)
    except PacketError as exc:
        print(f"[fail] {exc}", file=sys.stderr)
        return 1

    if errors:
        for error in errors:
            print(f"[fail] {error}", file=sys.stderr)
        return 1

    if args.check:
        print("[ok] App Store Connect entry packet is valid")
        return 0

    if args.json:
        print(json.dumps(packet, indent=2, sort_keys=True))
    else:
        print_markdown(packet)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
