#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${1:-$ROOT_DIR/Artifacts/AppStoreScreenshots}"
OUTPUT_DIR="${2:-$ROOT_DIR/Artifacts/AppStoreScreenshotUpload}"

fail() {
    printf '[fail] %s\n' "$1" >&2
    exit 1
}

check_image_size() {
    local path="$1"
    local expected_width="$2"
    local expected_height="$3"

    if [[ ! -f "$path" ]]; then
        fail "Missing screenshot: $path"
    fi

    local width height
    width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"

    if [[ "$width" != "$expected_width" || "$height" != "$expected_height" ]]; then
        fail "$(basename "$path") is ${width:-unknown}x${height:-unknown}; expected ${expected_width}x${expected_height}"
    fi
}

copy_slot() {
    local family_dir="$1"
    local source_name="$2"
    local target_name="$3"
    local expected_width="$4"
    local expected_height="$5"

    check_image_size "$INPUT_DIR/$source_name" "$expected_width" "$expected_height"
    cp "$INPUT_DIR/$source_name" "$family_dir/$target_name"
    printf '[ok] %s -> %s\n' "$source_name" "$target_name"
}

if [[ ! -d "$INPUT_DIR" ]]; then
    fail "Input screenshot directory missing: $INPUT_DIR"
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/iphone-6.9" "$OUTPUT_DIR/ipad-13"

printf 'Packaging App Store screenshots\n'
printf 'Input: %s\n' "$INPUT_DIR"
printf 'Output: %s\n\n' "$OUTPUT_DIR"

copy_slot "$OUTPUT_DIR/iphone-6.9" "iphone-17-pro-max-dashboard.png" "01-dashboard.png" 1320 2868
copy_slot "$OUTPUT_DIR/iphone-6.9" "iphone-17-pro-max-work-map.png" "02-work-map.png" 1320 2868
copy_slot "$OUTPUT_DIR/iphone-6.9" "iphone-17-pro-max-journal.png" "03-journal.png" 1320 2868
copy_slot "$OUTPUT_DIR/iphone-6.9" "iphone-17-pro-max-repositories.png" "04-repositories.png" 1320 2868
copy_slot "$OUTPUT_DIR/iphone-6.9" "iphone-17-pro-max-ai.png" "05-ai-providers.png" 1320 2868
copy_slot "$OUTPUT_DIR/iphone-6.9" "iphone-17-pro-max-privacy.png" "06-privacy-data.png" 1320 2868

copy_slot "$OUTPUT_DIR/ipad-13" "ipad-pro-13-dashboard.png" "01-dashboard.png" 2064 2752
copy_slot "$OUTPUT_DIR/ipad-13" "ipad-pro-13-work-map.png" "02-work-map.png" 2064 2752
copy_slot "$OUTPUT_DIR/ipad-13" "ipad-pro-13-journal.png" "03-journal.png" 2064 2752
copy_slot "$OUTPUT_DIR/ipad-13" "ipad-pro-13-repositories.png" "04-repositories.png" 2064 2752
copy_slot "$OUTPUT_DIR/ipad-13" "ipad-pro-13-ai.png" "05-ai-providers.png" 2064 2752
copy_slot "$OUTPUT_DIR/ipad-13" "ipad-pro-13-privacy.png" "06-privacy-data.png" 2064 2752

cat > "$OUTPUT_DIR/README.md" <<'README'
# Captain's Log Screenshot Upload Order

Use the same order for the 6.9-inch iPhone and 13-inch iPad screenshot sets.

1. `01-dashboard.png` - Shows the core daily overview, week strip, metric lens, and Work Map.
2. `02-work-map.png` - Makes the contribution-style history surface the visual identity.
3. `03-journal.png` - Shows the readable daily journal backed by commit evidence.
4. `04-repositories.png` - Shows repository selection and GitHub access control.
5. `05-ai-providers.png` - Shows optional bring-your-own-key AI providers.
6. `06-privacy-data.png` - Shows local-first privacy and data controls.

Before upload:

- Do not use screenshots with real private repository names.
- Keep the dashboard and Work Map first; those are the clearest product promise.
- Re-run `Scripts/app_store_preflight.sh <source-screenshot-dir>` after capturing new screenshots.
README

printf '\nPackaged screenshots in %s\n' "$OUTPUT_DIR"
