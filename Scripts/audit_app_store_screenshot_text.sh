#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCREENSHOT_DIR="${1:-/tmp/captainslog-key-state-packaged}"
OUTPUT_FILE="${CAPTAINS_LOG_SCREENSHOT_TEXT_AUDIT_OUTPUT:-}"

failures=0

pass() {
    printf '[ok] %s\n' "$1"
}

fail() {
    printf '[fail] %s\n' "$1" >&2
    failures=$((failures + 1))
}

printf "Captain's Log screenshot text audit\n"
printf 'Screenshots: %s\n\n' "$SCREENSHOT_DIR"

if ! command -v xcrun >/dev/null 2>&1; then
    fail "xcrun missing"
fi

if ! command -v rg >/dev/null 2>&1; then
    fail "rg missing"
fi

if ! xcrun swift --version >/dev/null 2>&1; then
    fail "xcrun swift unavailable"
fi

if [[ ! -d "$SCREENSHOT_DIR" ]]; then
    fail "screenshot directory missing: $SCREENSHOT_DIR"
fi

if (( failures > 0 )); then
    exit 1
fi

screenshots=()
while IFS= read -r screenshot_path; do
    screenshots+=("$screenshot_path")
done < <(find "$SCREENSHOT_DIR" -type f -name '*.png' | sort)
if (( ${#screenshots[@]} == 0 )); then
    fail "no PNG screenshots found under $SCREENSHOT_DIR"
    exit 1
fi

swift_source="$(mktemp -t captainslog-screenshot-ocr.XXXXXX.swift)"
ocr_output="$(mktemp -t captainslog-screenshot-ocr-output.XXXXXX)"
ocr_text_only="$(mktemp -t captainslog-screenshot-ocr-text.XXXXXX)"
cleanup() {
    rm -f "$swift_source" "$ocr_output" "$ocr_text_only"
}
trap cleanup EXIT

cat > "$swift_source" <<'SWIFT'
import Foundation
import Vision

let paths = Array(CommandLine.arguments.dropFirst())
if paths.isEmpty {
    FileHandle.standardError.write(Data("No screenshot paths provided.\n".utf8))
    exit(2)
}

var allLines: [String] = []
var failures: [String] = []

for path in paths {
    let url = URL(fileURLWithPath: path)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false

    do {
        let handler = VNImageRequestHandler(url: url, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        for observation in observations {
            guard let text = observation.topCandidates(1).first?.string else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            allLines.append("\(path)\t\(trimmed)")
        }
    } catch {
        failures.append("\(path): \(error)")
    }
}

for line in allLines {
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

if ! xcrun swift "$swift_source" "${screenshots[@]}" > "$ocr_output"; then
    fail "Vision OCR failed"
    exit 1
fi

line_count="$(wc -l < "$ocr_output" | tr -d ' ')"
if [[ "$line_count" == "0" ]]; then
    fail "Vision OCR returned no text"
else
    pass "Vision OCR lines: $line_count"
fi

if [[ -n "$OUTPUT_FILE" ]]; then
    cp "$ocr_output" "$OUTPUT_FILE"
    pass "OCR output written: $OUTPUT_FILE"
fi

cut -f2- "$ocr_output" > "$ocr_text_only"
rejected_pattern='fixture|UI Fixture|screen QA|debug|simulator|syncing|refreshing|Network|401|404|failed|error|blakecrosley|ghp_|github_pat_|sk-[A-Za-z0-9]|CAPTAINS_LOG|REPS_DEBUG|localhost|127[.]0[.]0[.]1|token|api key|private key'
if rejected_hits="$(rg -n -i "$rejected_pattern" "$ocr_text_only")"; then
    fail "screenshot OCR found rejected App Store text:
$(printf '%s\n' "$rejected_hits" | sed -n '1,20p')"
else
    pass "screenshot OCR found no rejected App Store text"
fi

printf '\n'
if (( failures > 0 )); then
    printf 'Screenshot text audit failed with %d issue(s).\n' "$failures" >&2
    exit 1
fi

printf 'Screenshot text audit passed.\n'
