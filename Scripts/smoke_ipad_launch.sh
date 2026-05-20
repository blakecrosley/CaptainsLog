#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CaptainsLog.xcodeproj"
SCHEME="CaptainsLog-iOS"
BUNDLE_ID="com.blakecrosley.captainslog"
OUTPUT_DIR="${1:-/tmp/captainslog-ipad-smoke}"
DERIVED_DATA_DIR="${CAPTAINS_LOG_IPAD_DERIVED_DATA:-/tmp/captainslog-ipad-smoke-release-build}"
IPAD_DEVICE_NAME="${IPAD_DEVICE_NAME:-iPad Pro 13-inch (M5)}"
IPAD_DEVICE_ID="${IPAD_DEVICE_ID:-}"

failures=0

pass() {
    printf '[ok] %s\n' "$1"
}

fail() {
    printf '[fail] %s\n' "$1" >&2
    failures=$((failures + 1))
}

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

metadata_value() {
    local plist_path="$1"
    local key="$2"
    plutil -extract "$key" raw -o - "$plist_path" 2>/dev/null || true
}

mkdir -p "$OUTPUT_DIR"
BUILD_LOG="$OUTPUT_DIR/ipad-release-build.log"
METADATA_OUTPUT="$OUTPUT_DIR/ipad-bundle-metadata.txt"
LAUNCH_LOG="$OUTPUT_DIR/ipad-launch.log"
SUMMARY_PATH="$OUTPUT_DIR/ipad-launch-summary.txt"

if ! command -v xcrun >/dev/null 2>&1; then
    fail "xcrun missing"
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
    fail "xcodebuild missing"
fi
if ! command -v plutil >/dev/null 2>&1; then
    fail "plutil missing"
fi
if ! command -v rg >/dev/null 2>&1; then
    fail "rg missing"
fi
if (( failures > 0 )); then
    exit 1
fi

if [[ -z "$IPAD_DEVICE_ID" ]]; then
    IPAD_DEVICE_ID="$(device_id_for_name "$IPAD_DEVICE_NAME")"
fi
if [[ -z "$IPAD_DEVICE_ID" ]]; then
    fail "missing available iPad simulator named: $IPAD_DEVICE_NAME"
    exit 1
fi
pass "iPad simulator selected: $IPAD_DEVICE_ID"

xcrun simctl boot "$IPAD_DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$IPAD_DEVICE_ID" -b >/dev/null
pass "iPad simulator booted"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "id=$IPAD_DEVICE_ID" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build | tee "$BUILD_LOG"

build_settings="$(mktemp)"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "id=$IPAD_DEVICE_ID" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    -showBuildSettings > "$build_settings"
target_build_dir="$(awk -F ' = ' '$1 ~ /TARGET_BUILD_DIR/ { print $2; exit }' "$build_settings")"
full_product_name="$(awk -F ' = ' '$1 ~ /FULL_PRODUCT_NAME/ { print $2; exit }' "$build_settings")"
rm -f "$build_settings"
app_path="$target_build_dir/$full_product_name"
info_plist="$app_path/Info.plist"

if [[ ! -d "$app_path" ]]; then
    fail "built iPad app not found: $app_path"
    exit 1
fi
pass "Release iPad app built: $app_path"

if [[ ! -f "$info_plist" ]]; then
    fail "Info.plist missing: $info_plist"
    exit 1
fi

bundle_id="$(metadata_value "$info_plist" CFBundleIdentifier)"
version="$(metadata_value "$info_plist" CFBundleShortVersionString)"
build="$(metadata_value "$info_plist" CFBundleVersion)"
device_family="$(plutil -extract UIDeviceFamily json -o - "$info_plist" 2>/dev/null || true)"

{
    printf 'App: %s\n' "$app_path"
    printf 'CFBundleIdentifier: %s\n' "$bundle_id"
    printf 'CFBundleShortVersionString: %s\n' "$version"
    printf 'CFBundleVersion: %s\n' "$build"
    printf 'UIDeviceFamily: %s\n' "$device_family"
} > "$METADATA_OUTPUT"
pass "bundle metadata written: $METADATA_OUTPUT"

if [[ "$bundle_id" == "$BUNDLE_ID" ]]; then
    pass "bundle id: $bundle_id"
else
    fail "bundle id mismatch: ${bundle_id:-missing}"
fi

if [[ "$version" == "1.0.0" && "$build" == "1" ]]; then
    pass "version/build: $version ($build)"
else
    fail "version/build mismatch: ${version:-missing} (${build:-missing})"
fi

if [[ "$device_family" == *"2"* ]]; then
    pass "UIDeviceFamily includes iPad"
else
    fail "UIDeviceFamily missing iPad: ${device_family:-missing}"
fi

xcrun simctl uninstall "$IPAD_DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$IPAD_DEVICE_ID" "$app_path"
pass "app installed on iPad simulator"

xcrun simctl launch --terminate-running-process "$IPAD_DEVICE_ID" "$BUNDLE_ID" | tee "$LAUNCH_LOG"
pass "app launch command returned"
if rg -q "^${BUNDLE_ID//./[.]}: [0-9]+" "$LAUNCH_LOG"; then
    pass "app launched on iPad simulator"
else
    fail "iPad simulator launch log did not include a process id"
fi

xcrun simctl terminate "$IPAD_DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
pass "app terminated on iPad simulator"

cat > "$SUMMARY_PATH" <<EOF
bundle_id=$BUNDLE_ID
device_id=$IPAD_DEVICE_ID
app_path=$app_path
build_log=$BUILD_LOG
metadata=$METADATA_OUTPUT
launch_log=$LAUNCH_LOG
screenshot=skipped
EOF

printf '\niPad launch smoke output:\n'
printf '  build log: %s\n' "$BUILD_LOG"
printf '  metadata: %s\n' "$METADATA_OUTPUT"
printf '  launch log: %s\n' "$LAUNCH_LOG"
printf '  summary: %s\n' "$SUMMARY_PATH"

if (( failures > 0 )); then
    printf '\niPad launch smoke failed with %d issue(s).\n' "$failures" >&2
    exit 1
fi

printf '\niPad launch smoke passed without screenshot capture.\n'
