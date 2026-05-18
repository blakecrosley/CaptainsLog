#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CaptainsLog.xcodeproj"
SCHEME="CaptainsLog-macOS"
BUNDLE_ID="com.blakecrosley.captainslog.mac"
OUTPUT_DIR="${1:-/tmp/captainslog-macos-appstore-screenshots}"
DERIVED_DATA_DIR="${CAPTAINS_LOG_MACOS_SCREENSHOT_DERIVED_DATA:-/tmp/captainslog-macos-debug-screenshot-build}"
WINDOW_WIDTH="${CAPTAINS_LOG_MACOS_SCREENSHOT_WINDOW_WIDTH:-1440}"
WINDOW_HEIGHT="${CAPTAINS_LOG_MACOS_SCREENSHOT_WINDOW_HEIGHT:-900}"
LAUNCH_WAIT_SECONDS="${CAPTAINS_LOG_MACOS_SCREENSHOT_LAUNCH_WAIT_SECONDS:-3}"
CAPTURE_DELAY_SECONDS="${CAPTAINS_LOG_MACOS_SCREENSHOT_CAPTURE_DELAY_SECONDS:-1}"
SCREENSHOT_OPENAI_KEY="${CAPTAINS_LOG_SCREENSHOT_OPENAI_KEY:-$(printf '%s-%s' "sk" "captainslog-screenshot-demo26")}"

failures=0

pass() {
    printf '[ok] %s\n' "$1"
}

fail() {
    printf '[fail] %s\n' "$1" >&2
    failures=$((failures + 1))
}

need_command() {
    if command -v "$1" >/dev/null 2>&1; then
        pass "command available: $1"
    else
        fail "command missing: $1"
    fi
}

metadata_value() {
    local plist_path="$1"
    local key="$2"
    plutil -extract "$key" raw -o - "$plist_path" 2>/dev/null || true
}

executable_path_for_app() {
    printf '%s/Contents/MacOS/Captain'\''s Log\n' "$1"
}

quit_or_kill() {
    local app_path="$1"
    local executable_path
    local pid

    executable_path="$(executable_path_for_app "$app_path")"
    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        kill "$pid" >/dev/null 2>&1 || true
    done < <(pgrep -f "$executable_path" || true)
    sleep 1
}

pid_for_app_path() {
    local app_path="$1"
    local executable_path
    local attempts=0
    local pid

    executable_path="$(executable_path_for_app "$app_path")"
    while (( attempts < 20 )); do
        pid="$(pgrep -f "$executable_path" | head -n 1 || true)"
        if [[ -n "$pid" ]]; then
            printf '%s\n' "$pid"
            return 0
        fi

        attempts=$((attempts + 1))
        sleep 0.5
    done

    return 1
}

png_size() {
    local path="$1"
    local width height

    width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth:/ { print $2; exit }')"
    height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight:/ { print $2; exit }')"

    printf '%sx%s\n' "$width" "$height"
}

check_mac_png_size() {
    local path="$1"
    local label="$2"
    local size

    size="$(png_size "$path")"

    case "$size" in
        1280x800|1440x900|2560x1600|2880x1800)
            pass "$label dimensions: $size"
            ;;
        *)
            fail "$label dimensions: ${size:-unknown}, expected an accepted Mac App Store size"
            ;;
    esac

}

make_window_helper() {
    local helper_path="$1"

    cat > "$helper_path" <<'SWIFT'
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let targetPID = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window-helper <pid>\n".utf8))
    exit(2)
}

guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("unable to list windows\n".utf8))
    exit(1)
}

struct Candidate {
    let id: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let name: String

    var area: Int { width * height }
}

let candidates = list.compactMap { item -> Candidate? in
    guard (item[kCGWindowOwnerPID as String] as? Int) == targetPID,
          (item[kCGWindowLayer as String] as? Int) == 0,
          let id = item[kCGWindowNumber as String] as? Int,
          let bounds = item[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Int,
          let height = bounds["Height"] as? Int,
          let x = bounds["X"] as? Int,
          let y = bounds["Y"] as? Int,
          width >= 100,
          height >= 100 else {
        return nil
    }

    return Candidate(
        id: id,
        x: x,
        y: y,
        width: width,
        height: height,
        name: item[kCGWindowName as String] as? String ?? ""
    )
}
.sorted { lhs, rhs in
    if lhs.area == rhs.area {
        return lhs.id > rhs.id
    }
    return lhs.area > rhs.area
}

guard let window = candidates.first else {
    FileHandle.standardError.write(Data("no visible app window found for pid \(targetPID)\n".utf8))
    exit(1)
}

print("\(window.id)\t\(window.x)\t\(window.y)\t\(window.width)\t\(window.height)\t\(window.name)")
SWIFT
}

capture_route() {
    local filename="$1"
    local label="$2"
    local route="$3"
    local app_path="$4"
    local output_path="$5"
    local helper_path="$6"
    local manifest_path="$7"
    local launch_args=(
        --env CAPTAINS_LOG_UI_FIXTURE=1
        --env CAPTAINS_LOG_MACOS_SCREENSHOT_MODE=1
        --env "CAPTAINS_LOG_MACOS_SCREENSHOT_WINDOW_WIDTH=$WINDOW_WIDTH"
        --env "CAPTAINS_LOG_MACOS_SCREENSHOT_WINDOW_HEIGHT=$WINDOW_HEIGHT"
        --env "CAPTAINS_LOG_DEBUG_OPENAI_API_KEY=$SCREENSHOT_OPENAI_KEY"
    )
    local pid window_info window_id window_x window_y window_width window_height window_name png_size

    if [[ -n "$route" ]]; then
        launch_args+=(--env "CAPTAINS_LOG_SCREENSHOT_ROUTE=$route")
    fi

    quit_or_kill "$app_path"
    open -n -F "${launch_args[@]}" "$app_path"
    sleep "$LAUNCH_WAIT_SECONDS"

    if ! pid="$(pid_for_app_path "$app_path")"; then
        fail "$label app process not found"
        return
    fi
    sleep "$CAPTURE_DELAY_SECONDS"

    if ! window_info="$(xcrun swift "$helper_path" "$pid")"; then
        fail "$label window id lookup failed"
        return
    fi
    IFS=$'\t' read -r window_id window_x window_y window_width window_height window_name <<< "$window_info"

    if [[ -z "$window_id" ]]; then
        fail "$label window id missing"
        return
    fi

    printf '[ok] %s window id: %s (%sx%s at %s,%s)\n' "$label" "$window_id" "$window_width" "$window_height" "$window_x" "$window_y"
    if ! screencapture -x -o -l "$window_id" "$output_path"; then
        sleep 1
        if ! window_info="$(xcrun swift "$helper_path" "$pid")"; then
            fail "$label retry window id lookup failed"
            return
        fi
        IFS=$'\t' read -r window_id window_x window_y window_width window_height window_name <<< "$window_info"
        printf '[ok] %s retry window id: %s (%sx%s at %s,%s)\n' "$label" "$window_id" "$window_width" "$window_height" "$window_x" "$window_y"
        if ! screencapture -x -o -l "$window_id" "$output_path"; then
            fail "$label window-only capture failed for window id $window_id"
            return
        fi
    fi
    check_mac_png_size "$output_path" "$filename"
    png_size="$(png_size "$output_path")"

    {
        printf 'file: %s\n' "$filename"
        printf 'label: %s\n' "$label"
        printf 'route: %s\n' "${route:-dashboard}"
        printf 'pid: %s\n' "$pid"
        printf 'window_id: %s\n' "$window_id"
        printf 'window_bounds_points: %sx%s at %s,%s\n' "$window_width" "$window_height" "$window_x" "$window_y"
        printf 'window_name: %s\n' "$window_name"
        printf 'png_size: %s\n' "$png_size"
        printf '\n'
    } >> "$manifest_path"
}

need_command git
need_command xcodebuild
need_command xcrun
need_command open
need_command screencapture
need_command sips
need_command plutil

if (( failures > 0 )); then
    exit 1
fi

staging_dir="$(mktemp -d "${OUTPUT_DIR%/}.staged.XXXXXX")"
window_helper="$(mktemp -t captainslog-macos-window-helper.XXXXXX.swift)"
trap 'rm -rf "$staging_dir" "$window_helper"; if [[ -n "${app_path:-}" ]]; then quit_or_kill "$app_path"; fi' EXIT

make_window_helper "$window_helper"

build_log="$staging_dir/macos-screenshot-build.log"
manifest_path="$staging_dir/macos-screenshot-manifest.txt"
metadata_path="$staging_dir/macos-bundle-metadata.txt"
audit_log="$staging_dir/macos-screenshot-text-audit.log"
ocr_output="$staging_dir/macos-screenshot-ocr.txt"

printf "Captain's Log macOS App Store screenshots\n" > "$manifest_path"
printf 'Generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$manifest_path"
printf 'Window target: %sx%s points\n\n' "$WINDOW_WIDTH" "$WINDOW_HEIGHT" >> "$manifest_path"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build | tee "$build_log"

build_settings="$(mktemp)"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    -showBuildSettings > "$build_settings"
target_build_dir="$(awk -F ' = ' '$1 ~ /TARGET_BUILD_DIR/ { print $2; exit }' "$build_settings")"
full_product_name="$(awk -F ' = ' '$1 ~ /FULL_PRODUCT_NAME/ { print $2; exit }' "$build_settings")"
rm -f "$build_settings"
app_path="$target_build_dir/$full_product_name"
info_plist="$app_path/Contents/Info.plist"

if [[ ! -d "$app_path" ]]; then
    fail "built app not found: $app_path"
    exit 1
fi
pass "Debug macOS app built: $app_path"

{
    printf 'App: %s\n' "$app_path"
    printf 'CFBundleIdentifier: %s\n' "$(metadata_value "$info_plist" CFBundleIdentifier)"
    printf 'CFBundleShortVersionString: %s\n' "$(metadata_value "$info_plist" CFBundleShortVersionString)"
    printf 'CFBundleVersion: %s\n' "$(metadata_value "$info_plist" CFBundleVersion)"
    printf 'LSApplicationCategoryType: %s\n' "$(metadata_value "$info_plist" LSApplicationCategoryType)"
    printf 'DTSDKName: %s\n' "$(metadata_value "$info_plist" DTSDKName)"
} > "$metadata_path"

routes=(
    "01-dashboard.png|Dashboard|"
    "02-work-map.png|Work Map|work-map"
    "03-journal.png|Journal|day-detail"
    "04-repositories.png|Repositories|repositories"
    "05-ai-providers.png|AI Providers|ai"
    "06-privacy-data.png|Privacy and Data|privacy"
)

for entry in "${routes[@]}"; do
    IFS='|' read -r filename label route <<< "$entry"
    capture_route "$filename" "$label" "$route" "$app_path" "$staging_dir/$filename" "$window_helper" "$manifest_path"
done

if (( failures > 0 )); then
    exit 1
fi

CAPTAINS_LOG_SCREENSHOT_TEXT_AUDIT_OUTPUT="$ocr_output" \
    "$ROOT_DIR/Scripts/audit_app_store_screenshot_text.sh" "$staging_dir" | tee "$audit_log"

rm -rf "$OUTPUT_DIR"
mv "$staging_dir" "$OUTPUT_DIR"
trap - EXIT
rm -f "$window_helper"
quit_or_kill "$app_path"

printf '\nmacOS screenshot output:\n'
printf '  screenshots: %s\n' "$OUTPUT_DIR"
printf '  manifest: %s\n' "$OUTPUT_DIR/macos-screenshot-manifest.txt"
printf '  text audit: %s\n' "$OUTPUT_DIR/macos-screenshot-text-audit.log"
printf '  OCR: %s\n' "$OUTPUT_DIR/macos-screenshot-ocr.txt"
