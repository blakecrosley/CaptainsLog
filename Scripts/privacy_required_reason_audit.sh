#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVACY_MANIFEST="$ROOT_DIR/CaptainsLog/Resources/PrivacyInfo.xcprivacy"

failures=0

fail() {
    printf '[fail] %s\n' "$1" >&2
    failures=$((failures + 1))
}

pass() {
    printf '[ok] %s\n' "$1"
}

warn() {
    printf '[warn] %s\n' "$1"
}

if [[ ! -f "$PRIVACY_MANIFEST" ]]; then
    fail "Privacy manifest missing: $PRIVACY_MANIFEST"
    exit 1
fi

source_roots=("$ROOT_DIR/CaptainsLog")
if [[ -d "$ROOT_DIR/../941Kit/Sources/Kit941" ]]; then
    source_roots+=("$ROOT_DIR/../941Kit/Sources/Kit941")
fi

rg_args=(
    --line-number
    --glob '*.swift'
    --glob '!Resources/PrivacyInfo.xcprivacy'
)

manifest_declares() {
    local category="$1"
    /usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes' "$PRIVACY_MANIFEST" 2>/dev/null | grep -q "$category"
}

check_category() {
    local category="$1"
    local label="$2"
    local pattern="$3"

    local matches
    matches="$(rg "${rg_args[@]}" "$pattern" "${source_roots[@]}" 2>/dev/null || true)"

    if [[ -n "$matches" ]]; then
        if manifest_declares "$category"; then
            pass "$label usage is declared"
            printf '%s\n' "$matches" | sed 's/^/  /'
        else
            fail "$label usage is missing from PrivacyInfo.xcprivacy"
            printf '%s\n' "$matches" | sed 's/^/  /' >&2
        fi
    elif manifest_declares "$category"; then
        warn "$label declared but no matching source usage was found"
    else
        pass "$label not detected"
    fi
}

printf 'Captain'\''s Log required reason API audit\n'
printf 'Privacy manifest: %s\n' "$PRIVACY_MANIFEST"
printf 'Source roots:\n'
for source_root in "${source_roots[@]}"; do
    printf '  %s\n' "$source_root"
done
printf '\n'

check_category \
    "NSPrivacyAccessedAPICategoryUserDefaults" \
    "UserDefaults" \
    '(@AppStorage|\bUserDefaults\b)'

check_category \
    "NSPrivacyAccessedAPICategoryFileTimestamp" \
    "File timestamp APIs" \
    '\b(creationDate|modificationDate|fileModificationDate|contentModificationDateKey|creationDateKey|getattrlist|getattrlistbulk|fgetattrlist|getattrlistat)\b|\b(stat|fstat|fstatat|lstat)\s*\('

check_category \
    "NSPrivacyAccessedAPICategorySystemBootTime" \
    "System boot time APIs" \
    '\b(systemUptime|mach_absolute_time)\b'

check_category \
    "NSPrivacyAccessedAPICategoryDiskSpace" \
    "Disk space APIs" \
    '\b(volumeAvailableCapacity|volumeAvailableCapacityForImportantUsage|volumeAvailableCapacityForOpportunisticUsage|volumeTotalCapacity|systemFreeSize|systemSize)\b|\b(statfs|statvfs|fstatfs|fstatvfs)\s*\('

check_category \
    "NSPrivacyAccessedAPICategoryActiveKeyboards" \
    "Active keyboard APIs" \
    '\b(activeInputModes|UITextInputMode)\b'

printf '\n'
if (( failures > 0 )); then
    printf 'Required reason API audit failed with %d issue(s).\n' "$failures" >&2
    exit 1
fi

printf 'Required reason API audit passed.\n'
