#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CaptainsLog.xcodeproj"
SCHEME="CaptainsLog-macOS"
BUNDLE_ID="com.blakecrosley.captainslog"
OUTPUT_DIR="${1:-/tmp/captainslog-macos-smoke}"
DERIVED_DATA_DIR="${CAPTAINS_LOG_MACOS_DERIVED_DATA:-/tmp/captainslog-macos-release-build}"
LAUNCH_WAIT_SECONDS="${LAUNCH_WAIT_SECONDS:-3}"

failures=0
warnings=0

pass() {
    printf '[ok] %s\n' "$1"
}

warn() {
    printf '[warn] %s\n' "$1"
    warnings=$((warnings + 1))
}

fail() {
    printf '[fail] %s\n' "$1" >&2
    failures=$((failures + 1))
}

metadata_value() {
    local plist_path="$1"
    local key="$2"
    plutil -extract "$key" raw -o - "$plist_path" 2>/dev/null || true
}

pid_for_bundle_id() {
    osascript -e "tell application \"System Events\" to get unix id of first process whose bundle identifier is \"$BUNDLE_ID\"" 2>/dev/null || true
}

quit_or_kill() {
    local pid="$1"

    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 &
    local quit_pid=$!
    local waited=0
    while kill -0 "$quit_pid" >/dev/null 2>&1 && (( waited < 5 )); do
        sleep 1
        waited=$((waited + 1))
    done
    if kill -0 "$quit_pid" >/dev/null 2>&1; then
        kill "$quit_pid" >/dev/null 2>&1 || true
    fi
    wait "$quit_pid" >/dev/null 2>&1 || true

    sleep 1
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
        sleep 1
    fi
    if [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1; then
        kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
}

mkdir -p "$OUTPUT_DIR"
BUILD_LOG="$OUTPUT_DIR/macos-release-build.log"
METADATA_OUTPUT="$OUTPUT_DIR/macos-bundle-metadata.txt"
CODESIGN_OUTPUT="$OUTPUT_DIR/macos-codesign.txt"
LAUNCH_LOG="$OUTPUT_DIR/macos-launch.log"

if ! command -v xcodebuild >/dev/null 2>&1; then
    fail "xcodebuild missing"
fi
if ! command -v plutil >/dev/null 2>&1; then
    fail "plutil missing"
fi
if ! command -v codesign >/dev/null 2>&1; then
    fail "codesign missing"
fi
if ! command -v osascript >/dev/null 2>&1; then
    fail "osascript missing"
fi
if ! command -v open >/dev/null 2>&1; then
    fail "open missing"
fi
if (( failures > 0 )); then
    exit 1
fi

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build | tee "$BUILD_LOG"

build_settings="$(mktemp)"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
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
pass "Release macOS app built: $app_path"

if [[ ! -f "$info_plist" ]]; then
    fail "Info.plist missing: $info_plist"
    exit 1
fi

bundle_id="$(metadata_value "$info_plist" CFBundleIdentifier)"
version="$(metadata_value "$info_plist" CFBundleShortVersionString)"
build="$(metadata_value "$info_plist" CFBundleVersion)"
category="$(metadata_value "$info_plist" LSApplicationCategoryType)"
sdk_name="$(metadata_value "$info_plist" DTSDKName)"

{
    printf 'App: %s\n' "$app_path"
    printf 'CFBundleIdentifier: %s\n' "$bundle_id"
    printf 'CFBundleShortVersionString: %s\n' "$version"
    printf 'CFBundleVersion: %s\n' "$build"
    printf 'LSApplicationCategoryType: %s\n' "$category"
    printf 'DTSDKName: %s\n' "$sdk_name"
} > "$METADATA_OUTPUT"
pass "bundle metadata written: $METADATA_OUTPUT"

if [[ "$bundle_id" == "$BUNDLE_ID" ]]; then
    pass "bundle id: $bundle_id"
else
    fail "bundle id mismatch: $bundle_id"
fi
if [[ -n "$version" && -n "$build" ]]; then
    pass "version/build: $version ($build)"
else
    fail "version/build missing"
fi
if [[ "$category" == "public.app-category.developer-tools" ]]; then
    pass "Mac App Store category: $category"
else
    fail "Mac App Store category mismatch: $category"
fi

if codesign -dv "$app_path" > "$CODESIGN_OUTPUT" 2>&1; then
    pass "codesign details written: $CODESIGN_OUTPUT"
else
    fail "codesign inspection failed"
fi
if rg -q "TeamIdentifier=not set" "$CODESIGN_OUTPUT"; then
    warn "codesign TeamIdentifier is not set; Mac App Store signing/export remains open"
else
    pass "codesign TeamIdentifier is present"
fi

existing_pid="$(pid_for_bundle_id)"
if [[ -n "$existing_pid" ]]; then
    quit_or_kill "$existing_pid"
fi

open -n "$app_path"
sleep "$LAUNCH_WAIT_SECONDS"
pid="$(pid_for_bundle_id)"
if [[ -n "$pid" ]]; then
    printf '%s\n' "$pid" > "$LAUNCH_LOG"
    pass "macOS app launched with process: $pid"
else
    fail "macOS app process not found after launch"
fi

if [[ -n "${pid:-}" ]]; then
    quit_or_kill "$pid"
    if ps -p "$pid" >/dev/null 2>&1; then
        fail "macOS app process still running after quit/kill: $pid"
    else
        pass "macOS app quit cleanly"
    fi
fi

printf '\nmacOS launch smoke output:\n'
printf '  build log: %s\n' "$BUILD_LOG"
printf '  metadata: %s\n' "$METADATA_OUTPUT"
printf '  codesign: %s\n' "$CODESIGN_OUTPUT"
printf '  launch log: %s\n' "$LAUNCH_LOG"

if (( failures > 0 )); then
    printf '\nmacOS launch smoke failed with %d issue(s).\n' "$failures" >&2
    exit 1
fi

if (( warnings > 0 )); then
    printf '\nmacOS launch smoke passed with %d warning(s).\n' "$warnings"
else
    printf '\nmacOS launch smoke passed.\n'
fi
