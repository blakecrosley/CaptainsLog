#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-/tmp/captainslog-tvos-appstore-screenshots}"
SMOKE_DIR="$(mktemp -d "${OUTPUT_DIR%/}.smoke.XXXXXX")"
STAGING_DIR="$(mktemp -d "${OUTPUT_DIR%/}.staged.XXXXXX")"
SCREENSHOT_PATH="$STAGING_DIR/01-read-only-dashboard.png"
MANIFEST_PATH="$STAGING_DIR/tvos-screenshot-manifest.txt"
AUDIT_LOG="$STAGING_DIR/tvos-screenshot-text-audit.log"
OCR_OUTPUT="$STAGING_DIR/tvos-screenshot-ocr.txt"

cleanup() {
    rm -rf "$SMOKE_DIR" "$STAGING_DIR"
}
trap cleanup EXIT

png_size() {
    local path="$1"
    local width height

    width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth:/ { print $2; exit }')"
    height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight:/ { print $2; exit }')"
    printf '%sx%s\n' "$width" "$height"
}

"$ROOT_DIR/Scripts/smoke_tvos_launch.sh" "$SMOKE_DIR"
cp "$SMOKE_DIR/tvos-launch.png" "$SCREENSHOT_PATH"

size="$(png_size "$SCREENSHOT_PATH")"
case "$size" in
    1920x1080|3840x2160)
        ;;
    *)
        printf 'tvOS screenshot dimensions: %s, expected an App Store accepted Apple TV size\n' "${size:-unknown}" >&2
        exit 1
        ;;
esac

{
    printf "Captain's Log tvOS App Store screenshots\n"
    printf 'Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Source smoke directory: %s\n' "$SMOKE_DIR"
    printf 'file: 01-read-only-dashboard.png\n'
    printf 'label: Read-only Dashboard\n'
    printf 'png_size: %s\n' "$size"
} > "$MANIFEST_PATH"

CAPTAINS_LOG_SCREENSHOT_TEXT_AUDIT_OUTPUT="$OCR_OUTPUT" \
    "$ROOT_DIR/Scripts/audit_app_store_screenshot_text.sh" "$STAGING_DIR" | tee "$AUDIT_LOG"

rm -rf "$OUTPUT_DIR"
mv "$STAGING_DIR" "$OUTPUT_DIR"
trap - EXIT
rm -rf "$SMOKE_DIR"

printf '\ntvOS App Store screenshot output:\n'
printf '  screenshots: %s\n' "$OUTPUT_DIR"
printf '  manifest: %s\n' "$OUTPUT_DIR/tvos-screenshot-manifest.txt"
printf '  text audit: %s\n' "$OUTPUT_DIR/tvos-screenshot-text-audit.log"
printf '  OCR: %s\n' "$OUTPUT_DIR/tvos-screenshot-ocr.txt"
