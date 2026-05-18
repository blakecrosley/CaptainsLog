#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${1:-/tmp/captainslog-key-state-packaged}"
OUTPUT_DIR="${2:-/tmp/captainslog-appstore-review}"
THUMB_DIR="$OUTPUT_DIR/thumbs"
CONTACT_SHEET="$OUTPUT_DIR/contact-sheet.png"
README_PATH="$OUTPUT_DIR/README.md"

fail() {
    printf '[fail] %s\n' "$1" >&2
    exit 1
}

require_file() {
    local path="$1"
    [[ -f "$path" ]] || fail "Missing screenshot: $path"
}

make_thumb() {
    local source="$1"
    local target="$2"
    local size="$3"

    require_file "$source"
    magick "$source" \
        -resize "$size" \
        -bordercolor '#101014' \
        -border 16 \
        "$target"
}

append_row() {
    local output="$1"
    shift
    magick "$@" +append "$output"
}

if ! command -v magick >/dev/null 2>&1; then
    fail "ImageMagick 'magick' is required to create the contact sheet"
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$THUMB_DIR/iphone" "$THUMB_DIR/ipad"

printf "Captain's Log App Store screenshot contact sheet\n"
printf 'Input: %s\n' "$INPUT_DIR"
printf 'Output: %s\n\n' "$OUTPUT_DIR"

iphone_files=(
    01-dashboard.png
    02-work-map.png
    03-journal.png
    04-repositories.png
    05-ai-providers.png
    06-privacy-data.png
)

ipad_files=(
    01-dashboard.png
    02-work-map.png
    03-journal.png
    04-repositories.png
    05-ai-providers.png
    06-privacy-data.png
)

index=0
for file in "${iphone_files[@]}"; do
    index=$((index + 1))
    make_thumb "$INPUT_DIR/iphone-6.9/$file" "$THUMB_DIR/iphone/$index.png" 330x717
done

index=0
for file in "${ipad_files[@]}"; do
    index=$((index + 1))
    make_thumb "$INPUT_DIR/ipad-13/$file" "$THUMB_DIR/ipad/$index.png" 309x413
done

append_row "$THUMB_DIR/iphone-row-1.png" "$THUMB_DIR/iphone/1.png" "$THUMB_DIR/iphone/2.png" "$THUMB_DIR/iphone/3.png"
append_row "$THUMB_DIR/iphone-row-2.png" "$THUMB_DIR/iphone/4.png" "$THUMB_DIR/iphone/5.png" "$THUMB_DIR/iphone/6.png"
magick "$THUMB_DIR/iphone-row-1.png" "$THUMB_DIR/iphone-row-2.png" -append "$THUMB_DIR/iphone-sheet.png"

append_row "$THUMB_DIR/ipad-row-1.png" "$THUMB_DIR/ipad/1.png" "$THUMB_DIR/ipad/2.png" "$THUMB_DIR/ipad/3.png"
append_row "$THUMB_DIR/ipad-row-2.png" "$THUMB_DIR/ipad/4.png" "$THUMB_DIR/ipad/5.png" "$THUMB_DIR/ipad/6.png"
magick "$THUMB_DIR/ipad-row-1.png" "$THUMB_DIR/ipad-row-2.png" -append "$THUMB_DIR/ipad-sheet.png"

magick "$THUMB_DIR/iphone-sheet.png" "$THUMB_DIR/ipad-sheet.png" -append "$CONTACT_SHEET"

cat > "$README_PATH" <<'README'
# Captain's Log App Store Screenshot Review

Review `contact-sheet.png` before upload. It shows the packaged screenshots in App Store upload order:

1. Dashboard
2. Work Map
3. Journal
4. Repositories
5. AI providers
6. Privacy & Data

The first two rows are the 6.9-inch iPhone set. The last two rows are the 13-inch iPad set.

Acceptance notes:

- Dashboard and Work Map should communicate the product promise without extra marketing text.
- The set should show one calm progression: overview, long-range memory, journal evidence, repository access, optional AI keys, and privacy controls.
- Text should remain legible at App Store preview size; reject any screenshot with clipped headings, clipped controls, or dense unreadable body copy.
- The fixture account should stay neutral. Do not upload screenshots that show real private repository names, live tokens, personal email addresses, or personal GitHub data.
- No previous-app breadcrumbs, debug labels, fixture warnings, simulator chrome, or sync progress bars should be visible.
- The design should feel quiet, precise, and journal-like rather than like a generic analytics dashboard.

Approval checklist:

- iPhone and iPad sets each contain exactly these six screenshots in this order.
- The first screenshot makes Captain's Log understandable in under five seconds.
- At least one screenshot clearly shows the Work Map/histogram identity surface.
- At least one screenshot makes journal entries traceable to commit evidence.
- Repository access and Privacy & Data screenshots make GitHub permissions and data handling understandable.
- AI provider screenshots make cloud AI optional and key-backed, not required for the core app.
- No screenshot depends on color alone to explain state; labels and shape carry the meaning too.
README

printf '[ok] Contact sheet: %s\n' "$CONTACT_SHEET"
printf '[ok] Review notes: %s\n' "$README_PATH"
