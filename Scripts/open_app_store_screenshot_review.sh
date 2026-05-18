#!/usr/bin/env bash
set -euo pipefail

REVIEW_DIR="${CAPTAINS_LOG_SCREENSHOT_REVIEW:-${1:-/tmp/captainslog-appstore-review}}"
REVIEW_HTML="$REVIEW_DIR/review.html"
CONTACT_SHEET="$REVIEW_DIR/contact-sheet.png"
CHECKLIST="$REVIEW_DIR/README.md"

fail() {
    printf '[fail] %s\n' "$1" >&2
    exit 1
}

need_file() {
    local path="$1"
    local label="$2"
    [[ -f "$path" ]] || fail "$label missing: $path"
}

need_file "$REVIEW_HTML" "screenshot review page"
need_file "$CONTACT_SHEET" "screenshot contact sheet"
need_file "$CHECKLIST" "screenshot approval checklist"

if ! command -v open >/dev/null 2>&1; then
    fail "macOS open command is unavailable"
fi

printf '[ok] Screenshot review page: %s\n' "$REVIEW_HTML"
printf '[ok] Contact sheet: %s\n' "$CONTACT_SHEET"
printf '[ok] Approval checklist: %s\n' "$CHECKLIST"
open "$REVIEW_HTML"
