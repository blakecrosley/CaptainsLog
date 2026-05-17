#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CaptainsLog.xcodeproj"
SCHEME="CaptainsLog-iOS"
BUNDLE_ID="com.blakecrosley.captainslog"
OUTPUT_DIR="${1:-$ROOT_DIR/Artifacts/AppStoreScreenshots}"
PHONE_NAME="${PHONE_NAME:-iPhone 17 Pro Max}"
IPAD_NAME="${IPAD_NAME:-iPad Pro 13-inch (M5)}"

mkdir -p "$OUTPUT_DIR"

device_id_for_name() {
    local device_name="$1"

    xcrun simctl list devices available \
        | awk -v name="$device_name" '
            index($0, name) > 0 && $0 !~ /unavailable/ {
                if ($0 ~ /Booted/) {
                    print
                    exit
                }
                if (first == "") {
                    first = $0
                }
            }
            END {
                if (first != "") {
                    print first
                }
            }
        ' \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' \
        | head -n 1
}

boot_device() {
    local device_id="$1"

    xcrun simctl boot "$device_id" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$device_id" -b >/dev/null
}

capture_dashboard() {
    local device_id="$1"
    local slug="$2"
    local app_path="$3"
    local screen_slug="${4:-dashboard}"
    local route="${5:-}"
    local output_path="$OUTPUT_DIR/${slug}-${screen_slug}.png"

    boot_device "$device_id"
    xcrun simctl uninstall "$device_id" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$device_id" "$app_path"
    xcrun simctl ui "$device_id" appearance dark >/dev/null 2>&1 || true
    xcrun simctl status_bar "$device_id" override \
        --time 9:41 \
        --batteryState charged \
        --batteryLevel 100 \
        --wifiBars 3 \
        --cellularBars 4 >/dev/null 2>&1 || true

    if [[ -n "$route" ]]; then
        SIMCTL_CHILD_CAPTAINS_LOG_UI_FIXTURE=1 \
        SIMCTL_CHILD_CAPTAINS_LOG_SCREENSHOT_ROUTE="$route" \
            xcrun simctl launch --terminate-running-process "$device_id" "$BUNDLE_ID" >/dev/null
    else
        SIMCTL_CHILD_CAPTAINS_LOG_UI_FIXTURE=1 \
            xcrun simctl launch --terminate-running-process "$device_id" "$BUNDLE_ID" >/dev/null
    fi

    sleep "${SCREENSHOT_DELAY_SECONDS:-3}"
    xcrun simctl io "$device_id" screenshot "$output_path" >/dev/null
    printf '%s\n' "$output_path"
}

capture_screenshot_set() {
    local device_id="$1"
    local slug="$2"
    local app_path="$3"

    capture_dashboard "$device_id" "$slug" "$app_path" "dashboard"
    capture_dashboard "$device_id" "$slug" "$app_path" "work-map" "work-map"
    capture_dashboard "$device_id" "$slug" "$app_path" "journal" "day-detail"
    capture_dashboard "$device_id" "$slug" "$app_path" "repositories" "repositories"
    capture_dashboard "$device_id" "$slug" "$app_path" "ai" "ai"
    capture_dashboard "$device_id" "$slug" "$app_path" "privacy" "privacy"
}

phone_id="$(device_id_for_name "$PHONE_NAME")"
ipad_id="$(device_id_for_name "$IPAD_NAME")"

if [[ -z "$phone_id" ]]; then
    printf 'Missing simulator: %s\n' "$PHONE_NAME" >&2
    exit 1
fi

if [[ -z "$ipad_id" ]]; then
    printf 'Missing simulator: %s\n' "$IPAD_NAME" >&2
    exit 1
fi

boot_device "$phone_id"
boot_device "$ipad_id"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "id=$phone_id" \
    build

build_settings="$(mktemp)"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "id=$phone_id" \
    -showBuildSettings > "$build_settings"
target_build_dir="$(awk -F ' = ' '$1 ~ /TARGET_BUILD_DIR/ { print $2; exit }' "$build_settings")"
full_product_name="$(awk -F ' = ' '$1 ~ /FULL_PRODUCT_NAME/ { print $2; exit }' "$build_settings")"
rm -f "$build_settings"
app_path="$target_build_dir/$full_product_name"

if [[ ! -d "$app_path" ]]; then
    printf 'Built app not found: %s\n' "$app_path" >&2
    exit 1
fi

capture_screenshot_set "$phone_id" "iphone-17-pro-max" "$app_path"
capture_screenshot_set "$ipad_id" "ipad-pro-13" "$app_path"
