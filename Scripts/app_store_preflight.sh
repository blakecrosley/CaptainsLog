#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CaptainsLog.xcodeproj"
SCHEME="CaptainsLog-iOS"
METADATA_FILE="$ROOT_DIR/Docs/AppStoreMetadata.md"
INFO_PLIST="$ROOT_DIR/CaptainsLog/App/CaptainsLog-iOS-Info.plist"
PRIVACY_MANIFEST="$ROOT_DIR/CaptainsLog/Resources/PrivacyInfo.xcprivacy"
BACKGROUND_INDEXER_SOURCE="$ROOT_DIR/CaptainsLog/Services/BackgroundHistoryIndexer.swift"
EXPECTED_BACKGROUND_TASK_ID="com.blakecrosley.captainslog.history-index"
APP_ICON_DIR="$ROOT_DIR/CaptainsLog/Resources/Assets.xcassets/AppIcon.appiconset"
APP_ICON="$APP_ICON_DIR/app-icon-1024-marketing.png"
SCREENSHOT_DIR="${1:-$ROOT_DIR/Artifacts/AppStoreScreenshots}"

failures=0

pass() {
    printf '[ok] %s\n' "$1"
}

fail() {
    printf '[fail] %s\n' "$1" >&2
    failures=$((failures + 1))
}

warn() {
    printf '[warn] %s\n' "$1"
}

metadata_field() {
    local label="$1"
    awk -v label="$label" '
        $0 == label ":" || $0 == "## " label {
            waiting = 1
            next
        }
        waiting && /^```/ {
            in_block = 1
            waiting = 0
            next
        }
        in_block && /^```/ {
            exit
        }
        in_block {
            print
        }
    ' "$METADATA_FILE"
}

char_count() {
    printf '%s' "$1" | awk '{ total += length($0) } END { print total + (NR > 0 ? NR - 1 : 0) }'
}

byte_count() {
    LC_ALL=C printf '%s' "$1" | wc -c | tr -d ' '
}

check_max_chars() {
    local label="$1"
    local value="$2"
    local max="$3"
    local count
    count="$(char_count "$value")"
    if (( count <= max )); then
        pass "$label length: $count/$max"
    else
        fail "$label length: $count/$max"
    fi
}

check_max_bytes() {
    local label="$1"
    local value="$2"
    local max="$3"
    local count
    count="$(byte_count "$value")"
    if (( count <= max )); then
        pass "$label bytes: $count/$max"
    else
        fail "$label bytes: $count/$max"
    fi
}

check_required_field() {
    local label="$1"
    local value="$2"
    if [[ -n "$value" ]]; then
        pass "$label present"
    else
        fail "$label missing"
    fi
}

check_url() {
    local label="$1"
    local value="$2"
    check_required_field "$label" "$value"
    if [[ "$value" != https://* ]]; then
        fail "$label must be HTTPS"
        return
    fi

    if [[ "${SKIP_NETWORK_CHECKS:-0}" == "1" ]]; then
        pass "$label network check skipped"
        return
    fi

    if curl --fail --silent --show-error --location --max-time 15 --output /dev/null "$value"; then
        pass "$label reachable"
    else
        fail "$label not reachable: $value"
    fi
}

check_url_contains() {
    local label="$1"
    local value="$2"
    shift 2

    if [[ -z "$value" || "$value" != https://* ]]; then
        return
    fi

    if [[ "${SKIP_NETWORK_CHECKS:-0}" == "1" ]]; then
        pass "$label content check skipped"
        return
    fi

    local page
    if ! page="$(curl --fail --silent --show-error --location --max-time 15 "$value")"; then
        fail "$label content not reachable: $value"
        return
    fi

    local pattern
    for pattern in "$@"; do
        if printf '%s' "$page" | grep -Eiq "$pattern"; then
            pass "$label contains: $pattern"
        else
            fail "$label missing required content: $pattern"
        fi
    done

    if printf '%s' "$page" | grep -Eiq '941-analytics|track\.js|/collect|cloudflareinsights|beacon\.min\.js|data-cf-beacon'; then
        warn "$label page includes active analytics scripts; remove or confirm this is acceptable for the published policy/support page"
    fi
}

check_image_size() {
    local path="$1"
    local expected_width="$2"
    local expected_height="$3"
    local label="$4"

    if [[ ! -f "$path" ]]; then
        fail "$label missing: $path"
        return
    fi

    local width height
    width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"

    if [[ "$width" == "$expected_width" && "$height" == "$expected_height" ]]; then
        pass "$label dimensions: ${width}x${height}"
    else
        fail "$label dimensions: ${width:-unknown}x${height:-unknown}, expected ${expected_width}x${expected_height}"
    fi
}

check_image_no_alpha() {
    local path="$1"
    local label="$2"

    if [[ ! -f "$path" ]]; then
        fail "$label missing: $path"
        return
    fi

    local has_alpha
    has_alpha="$(sips -g hasAlpha "$path" 2>/dev/null | awk '/hasAlpha/ { print $2 }')"
    if [[ "$has_alpha" == "no" ]]; then
        pass "$label has no alpha channel"
    else
        fail "$label has alpha channel: ${has_alpha:-unknown}"
    fi
}

check_build_setting() {
    local settings_file="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual="$(awk -F ' = ' -v key="$key" '
        {
            setting = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", setting)
            if (setting == key) {
                print $2
                exit
            }
        }
    ' "$settings_file")"

    if [[ "$actual" == "$expected" ]]; then
        pass "$key: $actual"
    else
        fail "$key: ${actual:-missing}, expected $expected"
    fi
}

printf 'Captain'\''s Log App Store preflight\n'
printf 'Metadata: %s\n' "$METADATA_FILE"
printf 'Screenshots: %s\n\n' "$SCREENSHOT_DIR"

if [[ ! -f "$METADATA_FILE" ]]; then
    fail "Metadata file missing: $METADATA_FILE"
else
    name="$(metadata_field "Name")"
    subtitle="$(metadata_field "Subtitle")"
    promo="$(metadata_field "Promotional text")"
    description="$(metadata_field "Description")"
    keywords="$(metadata_field "Keywords")"
    review_notes="$(metadata_field "App Review Notes")"
    privacy_url="$(metadata_field "Privacy Policy URL")"
    support_url="$(metadata_field "Support URL")"

    check_required_field "Name" "$name"
    name_length="$(char_count "$name")"
    if (( name_length >= 2 && name_length <= 30 )); then
        pass "Name length: $name_length/30"
    else
        fail "Name length: $name_length/30, minimum 2"
    fi

    check_required_field "Subtitle" "$subtitle"
    check_max_chars "Subtitle" "$subtitle" 30
    check_max_chars "Promotional text" "$promo" 170
    check_max_chars "Description" "$description" 4000
    check_max_bytes "Keywords" "$keywords" 100
    check_max_bytes "App Review notes" "$review_notes" 4000
    check_url "Privacy Policy URL" "$privacy_url"
    check_url "Support URL" "$support_url"
    check_url_contains "Privacy Policy URL" "$privacy_url" \
        "Captain.?s Log" \
        "GitHub" \
        "Keychain" \
        "OpenAI" \
        "Anthropic" \
        "advertising SDKs|tracking SDKs|product analytics SDKs" \
        "blake@941apps\\.com"
    check_url_contains "Support URL" "$support_url" \
        "Captain.?s Log" \
        "GitHub" \
        "Keychain" \
        "OpenAI" \
        "Anthropic" \
        "blake@941apps\\.com"
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    fail "Info.plist missing: $INFO_PLIST"
else
    encryption_flag="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$INFO_PLIST")"
    if [[ "$encryption_flag" == "false" ]]; then
        pass "ITSAppUsesNonExemptEncryption=false"
    else
        fail "ITSAppUsesNonExemptEncryption is $encryption_flag"
    fi

    background_mode="$(/usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes:0' "$INFO_PLIST" 2>/dev/null || true)"
    if [[ "$background_mode" == "processing" ]]; then
        pass "UIBackgroundModes includes processing"
    else
        fail "UIBackgroundModes: ${background_mode:-missing}, expected processing"
    fi

    permitted_background_task="$(/usr/libexec/PlistBuddy -c 'Print :BGTaskSchedulerPermittedIdentifiers:0' "$INFO_PLIST" 2>/dev/null || true)"
    if [[ "$permitted_background_task" == "$EXPECTED_BACKGROUND_TASK_ID" ]]; then
        pass "BGTaskSchedulerPermittedIdentifiers includes $EXPECTED_BACKGROUND_TASK_ID"
    else
        fail "BGTaskSchedulerPermittedIdentifiers: ${permitted_background_task:-missing}, expected $EXPECTED_BACKGROUND_TASK_ID"
    fi

    if rg -q "static let taskIdentifier = \"$EXPECTED_BACKGROUND_TASK_ID\"" "$BACKGROUND_INDEXER_SOURCE"; then
        pass "Background indexer task identifier matches Info.plist"
    else
        fail "Background indexer task identifier does not match Info.plist"
    fi
fi

if [[ ! -f "$PRIVACY_MANIFEST" ]]; then
    fail "Privacy manifest missing: $PRIVACY_MANIFEST"
else
    tracking_flag="$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$PRIVACY_MANIFEST")"
    accessed_api="$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPIType' "$PRIVACY_MANIFEST")"
    accessed_reason="$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0' "$PRIVACY_MANIFEST")"

    [[ "$tracking_flag" == "false" ]] && pass "Privacy tracking disabled" || fail "Privacy tracking flag is $tracking_flag"
    [[ "$accessed_api" == "NSPrivacyAccessedAPICategoryUserDefaults" ]] && pass "Privacy manifest declares UserDefaults" || fail "Unexpected privacy API: $accessed_api"
    [[ "$accessed_reason" == "CA92.1" ]] && pass "Privacy manifest UserDefaults reason CA92.1" || fail "Unexpected UserDefaults reason: $accessed_reason"
fi

if "$ROOT_DIR/Scripts/privacy_required_reason_audit.sh"; then
    pass "Required reason API audit"
else
    fail "Required reason API audit"
fi

settings_file="$(mktemp -t captainslog-build-settings.XXXXXX)"
trap 'rm -f "$settings_file"' EXIT
xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -destination "generic/platform=iOS" -showBuildSettings > "$settings_file"
check_build_setting "$settings_file" "PRODUCT_BUNDLE_IDENTIFIER" "com.blakecrosley.captainslog"
check_build_setting "$settings_file" "MARKETING_VERSION" "1.0.0"
check_build_setting "$settings_file" "CURRENT_PROJECT_VERSION" "1"
check_build_setting "$settings_file" "IPHONEOS_DEPLOYMENT_TARGET" "26.0"
check_build_setting "$settings_file" "TARGETED_DEVICE_FAMILY" "1,2"

check_image_size "$APP_ICON" 1024 1024 "Marketing app icon"

icon_png_count=0
for icon_path in "$APP_ICON_DIR"/*.png; do
    icon_png_count=$((icon_png_count + 1))
    check_image_no_alpha "$icon_path" "App icon $(basename "$icon_path")"
done
if (( icon_png_count == 0 )); then
    fail "No app icon PNGs found in $APP_ICON_DIR"
fi

if [[ ! -d "$SCREENSHOT_DIR" ]]; then
    fail "Screenshot directory missing: $SCREENSHOT_DIR"
else
    expected_screens=(
        "iphone-17-pro-max-dashboard.png"
        "iphone-17-pro-max-work-map.png"
        "iphone-17-pro-max-journal.png"
        "iphone-17-pro-max-repositories.png"
        "iphone-17-pro-max-ai.png"
        "iphone-17-pro-max-privacy.png"
        "ipad-pro-13-dashboard.png"
        "ipad-pro-13-work-map.png"
        "ipad-pro-13-journal.png"
        "ipad-pro-13-repositories.png"
        "ipad-pro-13-ai.png"
        "ipad-pro-13-privacy.png"
    )

    for screen in "${expected_screens[@]}"; do
        case "$screen" in
            iphone-17-pro-max-*) check_image_size "$SCREENSHOT_DIR/$screen" 1320 2868 "$screen" ;;
            ipad-pro-13-*) check_image_size "$SCREENSHOT_DIR/$screen" 2064 2752 "$screen" ;;
        esac
    done
fi

printf '\n'
if (( failures > 0 )); then
    printf 'Preflight failed with %d issue(s).\n' "$failures" >&2
    exit 1
fi

printf 'Preflight passed.\n'
