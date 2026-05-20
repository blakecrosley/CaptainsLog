#!/usr/bin/env python3
"""Print and validate held App Store platform-version copy."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_MARKETING_PATH = ROOT_DIR / "Docs" / "AppStoreMarketingPacket.md"


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


@dataclass(frozen=True)
class HeldField:
    key: str
    label: str
    platform: str
    max_chars: int | None = None
    required_phrase: str | None = None


HELD_FIELDS = (
    HeldField("all_platform_copy", "All-platform copy to use only after `Scripts/print_platform_readiness_matrix.py --require-store` passes", "All platforms"),
    HeldField("mac_promotional_text", "Native Mac promotional text", "Mac", max_chars=170),
    HeldField("mac_description_addendum", "Native Mac description addendum", "Mac", max_chars=4000, required_phrase="Do not use this copy"),
    HeldField("watch_description_addendum", "Apple Watch description addendum", "Apple Watch", max_chars=4000, required_phrase="Do not use this copy"),
    HeldField("tv_promotional_text", "Apple TV promotional text", "Apple TV", max_chars=170),
    HeldField("tv_description_addendum", "Apple TV description addendum", "Apple TV", max_chars=4000, required_phrase="Do not use this copy"),
    HeldField("native_visionos_guard", "Native visionOS copy", "Native visionOS", max_chars=4000, required_phrase="Do not add native visionOS copy"),
)


class PacketError(Exception):
    pass


def extract_text_block(markdown: str, label: str) -> str:
    pattern = re.compile(
        rf"^{re.escape(label)}:\s*\n\s*```text\n(?P<value>.*?)\n```",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(markdown)
    if not match:
        raise PacketError(f"Could not find text block for '{label}'")
    return match.group("value").strip()


def build_packet(marketing_path: Path) -> dict[str, Any]:
    markdown = marketing_path.read_text(encoding="utf-8")
    if "## Held Platform Version Copy" not in markdown:
        raise PacketError("Could not find '## Held Platform Version Copy'")

    fields: dict[str, dict[str, Any]] = {}
    for spec in HELD_FIELDS:
        value = extract_text_block(markdown, spec.label)
        fields[spec.key] = {
            "platform": spec.platform,
            "label": spec.label,
            "value": value,
            "characters": len(value),
            "max_characters": spec.max_chars,
        }

    return {
        "source": str(marketing_path.relative_to(ROOT_DIR)),
        "status": "held",
        "use_only_after": [
            "matching signed export",
            "TestFlight processing",
            "platform QA",
            "provisioning validation",
            "store-media acceptance",
            "Scripts/print_platform_readiness_matrix.py --require-store for all-platform public claims",
        ],
        "private_fields": [
            "App Review contact",
            "Demo GitHub review account credentials",
            "EU DSA trader contact details",
            "Apple IDs",
            "API key ID, issuer ID, and .p8 private key path",
        ],
        "fields": fields,
    }


def validate_packet(packet: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    values = {key: item["value"] for key, item in packet["fields"].items()}

    for spec in HELD_FIELDS:
        value = values.get(spec.key, "")
        if not value:
            errors.append(f"{spec.label} is empty")
        if spec.max_chars is not None and len(value) > spec.max_chars:
            errors.append(f"{spec.label} is {len(value)} characters, max {spec.max_chars}")
        if spec.required_phrase is not None and spec.required_phrase not in value:
            errors.append(f"{spec.label} must include guard phrase {spec.required_phrase!r}")

    all_text = "\n".join(values.values())
    for marker in PRIVATE_MARKERS:
        if marker in all_text:
            errors.append(f"held platform copy contains private/local marker {marker!r}")

    if "Scripts/print_platform_readiness_matrix.py --require-store" not in packet["fields"]["all_platform_copy"]["label"]:
        errors.append("all-platform copy label must keep the --require-store gate")

    return errors


def print_markdown(packet: dict[str, Any]) -> None:
    print("# Captain's Log Held Platform Marketing Packet")
    print()
    print(f"Source: `{packet['source']}`")
    print()
    print("This packet is held copy. It does not create App Store records, mutate signing assets, run exports, or generate screenshots.")
    print()
    print("Use only after:")
    for value in packet["use_only_after"]:
        print(f"- {value}")
    print()

    for key, item in packet["fields"].items():
        print(f"## {item['platform']}")
        print()
        print(f"{item['label']}:")
        print()
        print("```text")
        print(item["value"])
        print("```")
        print()
        if item["max_characters"] is not None:
            print(f"Characters: {item['characters']}/{item['max_characters']}")
            print()

    print("Private fields to enter only inside App Store Connect:")
    for value in packet["private_fields"]:
        print(f"- {value}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--marketing",
        type=Path,
        default=DEFAULT_MARKETING_PATH,
        help="Path to Docs/AppStoreMarketingPacket.md",
    )
    parser.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    parser.add_argument("--check", action="store_true", help="Validate only")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    marketing_path = args.marketing.resolve()
    try:
        packet = build_packet(marketing_path)
        errors = validate_packet(packet)
    except PacketError as exc:
        print(f"[fail] {exc}", file=sys.stderr)
        return 1

    if errors:
        for error in errors:
            print(f"[fail] {error}", file=sys.stderr)
        return 1

    if args.check:
        print("[ok] held platform marketing packet is valid")
        return 0

    if args.json:
        print(json.dumps(packet, indent=2, sort_keys=True))
    else:
        print_markdown(packet)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
