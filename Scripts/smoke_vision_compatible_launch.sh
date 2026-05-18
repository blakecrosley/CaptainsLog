#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CaptainsLog.xcodeproj"
SCHEME="CaptainsLog-iOS"
BUNDLE_ID="com.blakecrosley.captainslog"
OUTPUT_DIR="${1:-/tmp/captainslog-vision-smoke}"
DERIVED_DATA_DIR="${CAPTAINS_LOG_VISION_DERIVED_DATA:-/tmp/captainslog-vision-compatible-release-build}"
VISION_DEVICE_NAME="${VISION_DEVICE_NAME:-Apple Vision Pro}"
VISION_DEVICE_ID="${VISION_DEVICE_ID:-}"
SCREENSHOT_DELAY_SECONDS="${SCREENSHOT_DELAY_SECONDS:-12}"
STRICT_KEYCHAIN="${CAPTAINS_LOG_VISION_SMOKE_STRICT_KEYCHAIN:-0}"

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

write_ocr_source() {
    local swift_source="$1"

    cat > "$swift_source" <<'SWIFT'
import Foundation
import Vision

let paths = Array(CommandLine.arguments.dropFirst())
if paths.isEmpty {
    FileHandle.standardError.write(Data("No screenshot paths provided.\n".utf8))
    exit(2)
}

var lines: [String] = []
var failures: [String] = []

for path in paths {
    let url = URL(fileURLWithPath: path)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false

    do {
        let handler = VNImageRequestHandler(url: url, options: [:])
        try handler.perform([request])
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first?.string else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            lines.append(trimmed)
        }
    } catch {
        failures.append("\(path): \(error)")
    }
}

for line in lines {
    print(line)
}

if !failures.isEmpty {
    FileHandle.standardError.write(Data("OCR failed for \(failures.count) screenshot(s):\n".utf8))
    for failure in failures {
        FileHandle.standardError.write(Data("\(failure)\n".utf8))
    }
    exit(1)
}
SWIFT
}

require_ocr_text() {
    local pattern="$1"
    local label="$2"

    if rg -q -i "$pattern" "$OCR_OUTPUT"; then
        pass "Vision screenshot OCR includes $label"
    else
        fail "Vision screenshot OCR missing $label"
    fi
}

mkdir -p "$OUTPUT_DIR"
SCREENSHOT_PATH="$OUTPUT_DIR/vision-compatible-launch.png"
OCR_OUTPUT="$OUTPUT_DIR/vision-compatible-launch-ocr.txt"
BUILD_LOG="$OUTPUT_DIR/vision-compatible-build.log"
LAUNCH_LOG="$OUTPUT_DIR/vision-compatible-launch.log"

if ! command -v xcrun >/dev/null 2>&1; then
    fail "xcrun missing"
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
    fail "xcodebuild missing"
fi
if ! command -v rg >/dev/null 2>&1; then
    fail "rg missing"
fi
if ! xcrun swift --version >/dev/null 2>&1; then
    fail "xcrun swift unavailable"
fi
if (( failures > 0 )); then
    exit 1
fi

if [[ -z "$VISION_DEVICE_ID" ]]; then
    VISION_DEVICE_ID="$(device_id_for_name "$VISION_DEVICE_NAME")"
fi
if [[ -z "$VISION_DEVICE_ID" ]]; then
    fail "missing available visionOS simulator named: $VISION_DEVICE_NAME"
    exit 1
fi
pass "visionOS simulator selected: $VISION_DEVICE_ID"

xcrun simctl boot "$VISION_DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$VISION_DEVICE_ID" -b >/dev/null
pass "visionOS simulator booted"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "id=$VISION_DEVICE_ID" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build | tee "$BUILD_LOG"

build_settings="$(mktemp)"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "id=$VISION_DEVICE_ID" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    -showBuildSettings > "$build_settings"
target_build_dir="$(awk -F ' = ' '$1 ~ /TARGET_BUILD_DIR/ { print $2; exit }' "$build_settings")"
full_product_name="$(awk -F ' = ' '$1 ~ /FULL_PRODUCT_NAME/ { print $2; exit }' "$build_settings")"
rm -f "$build_settings"
app_path="$target_build_dir/$full_product_name"

if [[ ! -d "$app_path" ]]; then
    fail "built app not found: $app_path"
    exit 1
fi
pass "Release compatible app built: $app_path"

xcrun simctl uninstall "$VISION_DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$VISION_DEVICE_ID" "$app_path"
pass "app installed on Vision simulator"

xcrun simctl launch --terminate-running-process "$VISION_DEVICE_ID" "$BUNDLE_ID" | tee "$LAUNCH_LOG"
pass "app launch command returned"

sleep "$SCREENSHOT_DELAY_SECONDS"
xcrun simctl io "$VISION_DEVICE_ID" screenshot "$SCREENSHOT_PATH" >/dev/null
pass "Vision screenshot captured: $SCREENSHOT_PATH"

swift_source="$(mktemp -t captainslog-vision-smoke-ocr.XXXXXX.swift)"
cleanup() {
    rm -f "$swift_source"
}
trap cleanup EXIT
write_ocr_source "$swift_source"

if xcrun swift "$swift_source" "$SCREENSHOT_PATH" > "$OCR_OUTPUT"; then
    pass "Vision screenshot OCR written: $OCR_OUTPUT"
else
    fail "Vision screenshot OCR failed"
    exit 1
fi

line_count="$(wc -l < "$OCR_OUTPUT" | tr -d ' ')"
if [[ "$line_count" == "0" ]]; then
    fail "Vision screenshot OCR returned no text"
else
    pass "Vision screenshot OCR lines: $line_count"
fi

require_ocr_text "Captain'?s Log" "Captain's Log"
require_ocr_text "Sign in with GitHub" "Sign in with GitHub"
require_ocr_text "Use Demo Data" "Use Demo Data"

if rg -q -i "Keychain returned status -34018" "$OCR_OUTPUT"; then
    if [[ "$STRICT_KEYCHAIN" == "1" ]]; then
        fail "Vision screenshot OCR found Keychain returned status -34018"
    else
        warn "Vision screenshot OCR found Keychain returned status -34018; signed TestFlight/auth behavior remains unverified"
    fi
else
    pass "Vision screenshot OCR did not find Keychain returned status -34018"
fi

printf '\nVision compatible launch smoke output:\n'
printf '  screenshot: %s\n' "$SCREENSHOT_PATH"
printf '  OCR: %s\n' "$OCR_OUTPUT"
printf '  build log: %s\n' "$BUILD_LOG"
printf '  launch log: %s\n' "$LAUNCH_LOG"

if (( failures > 0 )); then
    printf '\nVision compatible launch smoke failed with %d issue(s).\n' "$failures" >&2
    exit 1
fi

if (( warnings > 0 )); then
    printf '\nVision compatible launch smoke passed with %d warning(s).\n' "$warnings"
else
    printf '\nVision compatible launch smoke passed.\n'
fi
