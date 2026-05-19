#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CaptainsLog.xcodeproj"
SCHEME="CaptainsLog-watchOS"
BUNDLE_ID="com.blakecrosley.captainslog.watchkitapp"
OUTPUT_DIR="${1:-/tmp/captainslog-watchos-smoke}"
DERIVED_DATA_DIR="${CAPTAINS_LOG_WATCHOS_DERIVED_DATA:-/tmp/captainslog-watchos-smoke-release-build}"
WATCH_DEVICE_NAME="${WATCH_DEVICE_NAME:-Apple Watch Series 11 (46mm)}"
WATCH_DEVICE_ID="${WATCH_DEVICE_ID:-}"
SCREENSHOT_DELAY_SECONDS="${SCREENSHOT_DELAY_SECONDS:-4}"

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
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false

    do {
        let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:])
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

require_ocr_text_any() {
    local label="$1"
    shift
    local pattern

    for pattern in "$@"; do
        if rg -q -i "$pattern" "$OCR_OUTPUT"; then
            pass "watchOS launch OCR includes $label"
            return
        fi
    done

    fail "watchOS launch OCR missing $label"
}

mkdir -p "$OUTPUT_DIR"
SCREENSHOT_PATH="$OUTPUT_DIR/watchos-launch.png"
OCR_OUTPUT="$OUTPUT_DIR/watchos-launch-ocr.txt"
BUILD_LOG="$OUTPUT_DIR/watchos-release-build.log"
LAUNCH_LOG="$OUTPUT_DIR/watchos-launch.log"

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

if [[ -z "$WATCH_DEVICE_ID" ]]; then
    WATCH_DEVICE_ID="$(device_id_for_name "$WATCH_DEVICE_NAME")"
fi
if [[ -z "$WATCH_DEVICE_ID" ]]; then
    fail "missing available watchOS simulator named: $WATCH_DEVICE_NAME"
    exit 1
fi
pass "watchOS simulator selected: $WATCH_DEVICE_ID"

xcrun simctl boot "$WATCH_DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$WATCH_DEVICE_ID" -b >/dev/null
pass "watchOS simulator booted"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "id=$WATCH_DEVICE_ID" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build | tee "$BUILD_LOG"

build_settings="$(mktemp)"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "id=$WATCH_DEVICE_ID" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    -showBuildSettings > "$build_settings"
target_build_dir="$(awk -F ' = ' '$1 ~ /TARGET_BUILD_DIR/ { print $2; exit }' "$build_settings")"
full_product_name="$(awk -F ' = ' '$1 ~ /FULL_PRODUCT_NAME/ { print $2; exit }' "$build_settings")"
rm -f "$build_settings"
app_path="$target_build_dir/$full_product_name"

if [[ ! -d "$app_path" ]]; then
    fail "built watchOS app not found: $app_path"
    exit 1
fi
pass "Release watchOS app built: $app_path"

xcrun simctl uninstall "$WATCH_DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$WATCH_DEVICE_ID" "$app_path"
pass "app installed on Watch simulator"

xcrun simctl launch --terminate-running-process "$WATCH_DEVICE_ID" "$BUNDLE_ID" | tee "$LAUNCH_LOG"
pass "app launch command returned"

sleep "$SCREENSHOT_DELAY_SECONDS"
xcrun simctl io "$WATCH_DEVICE_ID" screenshot "$SCREENSHOT_PATH" >/dev/null
pass "watchOS screenshot captured: $SCREENSHOT_PATH"

width="$(sips -g pixelWidth "$SCREENSHOT_PATH" 2>/dev/null | awk '/pixelWidth:/ { print $2; exit }')"
height="$(sips -g pixelHeight "$SCREENSHOT_PATH" 2>/dev/null | awk '/pixelHeight:/ { print $2; exit }')"
if [[ -n "$width" && -n "$height" ]]; then
    pass "watchOS screenshot dimensions: ${width}x${height}"
else
    fail "unable to read watchOS screenshot dimensions"
fi

swift_source="$(mktemp -t captainslog-watchos-smoke-ocr.XXXXXX.swift)"
cleanup() {
    rm -f "$swift_source"
}
trap cleanup EXIT
write_ocr_source "$swift_source"

if xcrun swift "$swift_source" "$SCREENSHOT_PATH" > "$OCR_OUTPUT"; then
    pass "watchOS screenshot OCR written: $OCR_OUTPUT"
else
    fail "watchOS screenshot OCR failed"
    exit 1
fi

line_count="$(wc -l < "$OCR_OUTPUT" | tr -d ' ')"
if [[ "$line_count" == "0" ]]; then
    fail "watchOS screenshot OCR returned no text"
else
    pass "watchOS screenshot OCR lines: $line_count"
fi

require_ocr_text_any "companion UI" "Captain'?s Log" "Sync from iPhone" "Waiting" "Log"

printf '\nwatchOS launch smoke output:\n'
printf '  build log: %s\n' "$BUILD_LOG"
printf '  launch log: %s\n' "$LAUNCH_LOG"
printf '  screenshot: %s\n' "$SCREENSHOT_PATH"
printf '  OCR: %s\n' "$OCR_OUTPUT"

if (( failures > 0 )); then
    printf '\nwatchOS launch smoke failed with %d issue(s).\n' "$failures" >&2
    exit 1
fi

printf '\nwatchOS launch smoke passed.\n'
