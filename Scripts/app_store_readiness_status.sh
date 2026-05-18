#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_IPA="/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
SCREENSHOT_DIR="${1:-/tmp/captainslog-key-state-audit}"
IPA_PATH="${2:-$DEFAULT_IPA}"
EXPORT_MANIFEST="$(dirname "$IPA_PATH")/ExportManifest.txt"
PACKAGED_DIR="${CAPTAINS_LOG_PACKAGED_SCREENSHOTS:-/tmp/captainslog-key-state-packaged}"
SCREENSHOT_REVIEW_DIR="${CAPTAINS_LOG_SCREENSHOT_REVIEW:-/tmp/captainslog-appstore-review}"
KIT941_DIR="$ROOT_DIR/../941Kit"

local_failures=0
external_blockers=0

pass() {
    printf '[ok] %s\n' "$1"
}

warn() {
    printf '[warn] %s\n' "$1"
}

fail() {
    printf '[fail] %s\n' "$1" >&2
    local_failures=$((local_failures + 1))
}

external() {
    printf '[external] %s\n' "$1"
    external_blockers=$((external_blockers + 1))
}

need_command() {
    if command -v "$1" >/dev/null 2>&1; then
        pass "command available: $1"
    else
        fail "command missing: $1"
    fi
}

need_xcrun_tool() {
    if xcrun "$1" --help >/dev/null 2>&1; then
        pass "xcrun tool available: $1"
    else
        fail "xcrun tool missing or unavailable: $1"
    fi
}

manifest_value() {
    local label="$1"
    awk -F ': ' -v label="$label" '$1 == label { print $2; exit }' "$EXPORT_MANIFEST"
}

is_app_source_path() {
    case "$1" in
        CaptainsLog/*|CaptainsLog.xcodeproj/*|project.yml)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_kit_package_source_path() {
    case "$1" in
        Package.swift|Package.resolved|Sources/Kit941/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

absolute_path() {
    local path="$1"
    local dir
    dir="$(cd "$(dirname "$path")" && pwd -P)"
    printf '%s/%s\n' "$dir" "$(basename "$path")"
}

default_p8_path_for_key() {
    local api_key="$1"
    local expected_name="AuthKey_${api_key}.p8"
    local dirs=(
        "$PWD/private_keys"
        "$HOME/private_keys"
        "$HOME/.private_keys"
        "$HOME/.appstoreconnect/private_keys"
    )

    if [[ -n "${API_PRIVATE_KEYS_DIR:-}" ]]; then
        dirs+=("$API_PRIVATE_KEYS_DIR")
    fi

    local dir candidate
    for dir in "${dirs[@]}"; do
        candidate="$dir/$expected_name"
        if [[ -f "$candidate" ]]; then
            absolute_path "$candidate"
            return 0
        fi
    done

    return 1
}

check_p8_path() {
    local p8_path="$1"
    local source_label="$2"

    pass "App Store Connect .p8 key file found via $source_label"
    p8_path="$(absolute_path "$p8_path")"
    case "$p8_path" in
        "$ROOT_DIR"/*)
            fail "App Store Connect .p8 key file must live outside the repo"
            ;;
        *)
            pass "App Store Connect .p8 key file is outside the repo"
            ;;
    esac

    if [[ -r "$p8_path" ]]; then
        pass "App Store Connect .p8 key file is readable"
    else
        fail "App Store Connect .p8 key file is not readable"
    fi

    if rg -q -- "-----BEGIN PRIVATE KEY-----" "$p8_path"; then
        pass "App Store Connect .p8 key file has a private-key header"
    else
        fail "App Store Connect .p8 key file does not look like an App Store Connect private key"
    fi

    if [[ -n "${APP_STORE_CONNECT_API_KEY:-}" ]]; then
        expected_p8_name="AuthKey_${APP_STORE_CONNECT_API_KEY}.p8"
        if [[ "$(basename "$p8_path")" == "$expected_p8_name" ]]; then
            pass "App Store Connect .p8 filename matches the API key ID"
        else
            warn "App Store Connect .p8 filename is not $expected_p8_name; --p8-file-path may still work, but verify carefully"
        fi
    fi
}

printf "Captain's Log App Store readiness status\n"
printf 'Repo: %s\n' "$ROOT_DIR"
printf 'Screenshots: %s\n' "$SCREENSHOT_DIR"
printf 'Packaged screenshots: %s\n' "$PACKAGED_DIR"
printf 'Screenshot review: %s\n' "$SCREENSHOT_REVIEW_DIR"
printf 'IPA: %s\n\n' "$IPA_PATH"

need_command git
need_command xcrun
need_command xcodebuild
need_command sips
need_command sqlite3
need_command unzip
need_command rg
need_command magick
need_xcrun_tool altool

if xcode_version="$(xcodebuild -version 2>/dev/null)" && xcode_sdks="$(xcodebuild -showsdks 2>/dev/null)"; then
    xcode_first_line="$(printf '%s\n' "$xcode_version" | sed -n '1p')"
    if printf '%s\n' "$xcode_sdks" | rg -q 'iphoneos(2[6-9]|[3-9][0-9])([.]|$)'; then
        pass "$xcode_first_line with iOS 26 or newer SDK"
    else
        fail "$xcode_first_line does not list an iOS 26 or newer SDK required for 2026 App Store upload"
    fi
else
    fail "xcodebuild version or SDK list unavailable"
fi

printf '\nLocal artifact checks\n'
if [[ -f "$IPA_PATH" ]]; then
    pass "IPA exists"
else
    fail "IPA missing: $IPA_PATH"
fi

if [[ -f "$EXPORT_MANIFEST" ]]; then
    pass "export manifest exists"
else
    fail "export manifest missing: $EXPORT_MANIFEST"
fi

if [[ -d "$SCREENSHOT_DIR" ]]; then
    pass "screenshot source exists"
else
    fail "screenshot source missing: $SCREENSHOT_DIR"
fi

if [[ -d "$PACKAGED_DIR/iphone-6.9" && -d "$PACKAGED_DIR/ipad-13" ]]; then
    packaged_count="$(find "$PACKAGED_DIR" -maxdepth 2 -type f -name '*.png' | wc -l | tr -d ' ')"
    if [[ "$packaged_count" == "12" ]]; then
        pass "packaged screenshot count: 12"
    else
        fail "packaged screenshot count: ${packaged_count:-0}, expected 12"
    fi
else
    fail "packaged screenshot folders missing under $PACKAGED_DIR"
fi

if [[ -f "$SCREENSHOT_REVIEW_DIR/contact-sheet.png" ]]; then
    pass "screenshot review contact sheet exists"
else
    fail "screenshot review contact sheet missing: $SCREENSHOT_REVIEW_DIR/contact-sheet.png"
fi

if [[ -f "$SCREENSHOT_REVIEW_DIR/README.md" ]]; then
    if rg -q "Approval checklist" "$SCREENSHOT_REVIEW_DIR/README.md"; then
        pass "screenshot review checklist exists"
    else
        fail "screenshot review README missing approval checklist: $SCREENSHOT_REVIEW_DIR/README.md"
    fi
else
    fail "screenshot review README missing: $SCREENSHOT_REVIEW_DIR/README.md"
fi

if [[ -f "$SCREENSHOT_REVIEW_DIR/review.html" ]]; then
    if rg -q "Screenshot approval pass" "$SCREENSHOT_REVIEW_DIR/review.html"; then
        pass "screenshot review page exists"
    else
        fail "screenshot review page missing approval heading: $SCREENSHOT_REVIEW_DIR/review.html"
    fi
else
    fail "screenshot review page missing: $SCREENSHOT_REVIEW_DIR/review.html"
fi

printf '\nSource cleanliness\n'
repo_status="$(git -C "$ROOT_DIR" status --short)"
if [[ -z "$repo_status" ]]; then
    pass "CaptainsLog git tree clean"
else
    fail "CaptainsLog git tree is dirty:
$repo_status"
fi

if [[ -d "$KIT941_DIR/.git" ]]; then
    kit_status="$(git -C "$KIT941_DIR" status --short)"
    if [[ -z "$kit_status" ]]; then
        pass "Kit941 git tree clean"
    else
        kit_blocking_changes="$(
            {
                git -C "$KIT941_DIR" diff --name-only HEAD -- Package.swift Package.resolved Sources/Kit941
                git -C "$KIT941_DIR" ls-files --others --exclude-standard -- Package.swift Package.resolved Sources/Kit941
            } | sort -u
        )"
        if [[ -z "$kit_blocking_changes" ]]; then
            warn "Kit941 has dirty files outside the CaptainsLog-linked package source:
$kit_status"
        else
            fail "Kit941 package source changed after IPA export; regenerate IPA or restore these changes:
$kit_blocking_changes"
        fi
    fi
else
    warn "Kit941 git tree not found at $KIT941_DIR"
fi

if [[ -f "$EXPORT_MANIFEST" ]]; then
    exported_commit="$(manifest_value 'Exported app commit')"
    exported_dirty="$(manifest_value 'Git dirty at export')"
    exported_kit_commit="$(manifest_value 'Kit941 commit')"
    exported_kit_dirty="$(manifest_value 'Kit941 dirty at export')"
    current_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"

    if [[ "$exported_dirty" == "false" ]]; then
        pass "exported CaptainsLog tree was clean"
    else
        fail "exported CaptainsLog tree was dirty"
    fi

    if [[ "$exported_kit_dirty" == "false" ]]; then
        pass "exported Kit941 tree was clean"
    else
        fail "exported Kit941 tree was dirty or unknown: ${exported_kit_dirty:-missing}"
    fi

    if [[ "$exported_commit" == "$current_commit" ]]; then
        pass "IPA exported from current CaptainsLog commit"
    elif [[ -n "$exported_commit" ]]; then
        app_source_changes=""
        while IFS= read -r changed_path; do
            if is_app_source_path "$changed_path"; then
                app_source_changes+="${changed_path}"$'\n'
            fi
        done < <(git -C "$ROOT_DIR" diff --name-only "$exported_commit"..HEAD)

        if [[ -z "$app_source_changes" ]]; then
            pass "IPA app source still current; commits after export are docs/scripts only"
        else
            fail "app source changed after IPA export; regenerate IPA:
$app_source_changes"
        fi
    else
        fail "export manifest missing exported app commit"
    fi

    if [[ -d "$KIT941_DIR/.git" && -n "$exported_kit_commit" ]]; then
        current_kit_commit="$(git -C "$KIT941_DIR" rev-parse HEAD)"
        if [[ "$exported_kit_commit" == "$current_kit_commit" ]]; then
            pass "IPA exported from current Kit941 commit"
        else
            kit_source_changes=""
            while IFS= read -r changed_path; do
                if is_kit_package_source_path "$changed_path"; then
                    kit_source_changes+="${changed_path}"$'\n'
                fi
            done < <(git -C "$KIT941_DIR" diff --name-only "$exported_kit_commit"..HEAD)

            if [[ -z "$kit_source_changes" ]]; then
                pass "IPA Kit941 library source still current; commits after export are outside linked package source"
            else
                fail "Kit941 package source changed after IPA export; regenerate IPA:
$kit_source_changes"
            fi
        fi
    fi
fi

printf '\nPreflight\n'
if "$ROOT_DIR/Scripts/app_store_preflight.sh" "$SCREENSHOT_DIR"; then
    pass "App Store preflight"
else
    fail "App Store preflight failed"
fi

printf '\nIPA local check\n'
if "$ROOT_DIR/Scripts/upload_app_store_ipa.sh" local-check "$IPA_PATH"; then
    pass "IPA local check"
else
    fail "IPA local check failed"
fi

printf '\nExternal gates\n'
if [[ -n "${APP_STORE_CONNECT_API_KEY:-}" && -n "${APP_STORE_CONNECT_API_ISSUER:-}" ]]; then
    pass "App Store Connect API key and issuer are set"
    if [[ "$APP_STORE_CONNECT_API_KEY" =~ ^[A-Za-z0-9]{10}$ ]]; then
        pass "App Store Connect API key shape looks valid"
    else
        fail "App Store Connect API key should be a 10-character key ID"
    fi

    if [[ "$APP_STORE_CONNECT_API_ISSUER" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
        pass "App Store Connect issuer shape looks valid"
    else
        fail "App Store Connect issuer should be a UUID"
    fi
else
    external "App Store Connect API key and issuer are not set; validate/upload/status remain blocked"
fi

if [[ -n "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
    if [[ -f "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
        check_p8_path "$APP_STORE_CONNECT_P8_FILE" "APP_STORE_CONNECT_P8_FILE"
    else
        fail "APP_STORE_CONNECT_P8_FILE is set but the file does not exist: $APP_STORE_CONNECT_P8_FILE"
    fi
elif [[ -n "${APP_STORE_CONNECT_API_KEY:-}" ]] && default_p8_path="$(default_p8_path_for_key "$APP_STORE_CONNECT_API_KEY")"; then
    check_p8_path "$default_p8_path" "altool default private key search path"
else
    external "App Store Connect .p8 key file is not set and AuthKey_<key>.p8 was not found in altool's default private key search paths"
fi

external "create or confirm the App Store Connect app record with Scripts/upload_app_store_ipa.sh app-record"
external "complete manual App Store Connect fields from Docs/AppStoreMetadata.md, including regional availability prompts, EU DSA trader status, Labels and Markings URLs, regulated medical device status, and tax category if App Store Connect shows them"
external "upload build and verify TestFlight processing"
external "complete human screenshot marketing acceptance"
external "complete legal/privacy review"
pass "blakecrosley.com PR 15 source state reconciled"
external "final human tap-through on the real large-account install"

printf '\nSummary\n'
if (( local_failures > 0 )); then
    printf '[fail] Local readiness failed with %d issue(s).\n' "$local_failures" >&2
    exit 1
fi

pass "local readiness passed"
if (( external_blockers > 0 )); then
    printf '[external] %d external gate(s) remain before submission.\n' "$external_blockers"
    cat <<'NEXT_STEPS'

Next external actions:
1. Create or confirm the App Store Connect app record, then complete the manual fields from Docs/AppStoreMetadata.md, including regional availability prompts, EU DSA trader status, Labels and Markings URLs, regulated medical device status, and tax category if App Store Connect shows them.
2. Set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER, then either set APP_STORE_CONNECT_P8_FILE or place AuthKey_<key>.p8 in an altool default private key folder outside this repo.
3. Run:
   Scripts/upload_app_store_ipa.sh app-record "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
   Scripts/upload_app_store_ipa.sh validate "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
   Scripts/upload_app_store_ipa.sh upload "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
4. Open /tmp/captainslog-appstore-review/contact-sheet.png for human screenshot approval.
5. Complete legal/privacy review and final real-account tap-through before submitting.
NEXT_STEPS
fi
