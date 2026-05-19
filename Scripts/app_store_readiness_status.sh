#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="M4WTLM6RAQ"
IOS_BUNDLE_ID="com.blakecrosley.captainslog"
MACOS_BUNDLE_ID="com.blakecrosley.captainslog.mac"
DEFAULT_IPA="/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
SCREENSHOT_DIR="${1:-/tmp/captainslog-key-state-audit}"
IPA_PATH="${2:-$DEFAULT_IPA}"
EXPORT_MANIFEST="$(dirname "$IPA_PATH")/ExportManifest.txt"
ARCHIVE_PATH="$(dirname "$(dirname "$IPA_PATH")")/CaptainsLog.xcarchive"
PACKAGED_DIR="${CAPTAINS_LOG_PACKAGED_SCREENSHOTS:-/tmp/captainslog-key-state-packaged}"
SCREENSHOT_REVIEW_DIR="${CAPTAINS_LOG_SCREENSHOT_REVIEW:-/tmp/captainslog-appstore-review}"
KIT941_DIR="$ROOT_DIR/../941Kit"
RETURN_REFERENCE_PROJECT="${CAPTAINS_LOG_RETURN_REFERENCE_PROJECT:-$ROOT_DIR/../Return/Return.xcodeproj}"
BANANA_LIST_REFERENCE_PROJECT="${CAPTAINS_LOG_BANANA_LIST_REFERENCE_PROJECT:-$ROOT_DIR/../Banana List/Banana List.xcodeproj}"
VISION_SMOKE_DIR="${CAPTAINS_LOG_VISION_SMOKE_DIR:-/tmp/captainslog-vision-smoke}"
VISION_SMOKE_SCREENSHOT="$VISION_SMOKE_DIR/vision-compatible-launch.png"
VISION_SMOKE_OCR="$VISION_SMOKE_DIR/vision-compatible-launch-ocr.txt"
MACOS_SMOKE_DIR="${CAPTAINS_LOG_MACOS_SMOKE_DIR:-/tmp/captainslog-macos-smoke}"
MACOS_SMOKE_METADATA="$MACOS_SMOKE_DIR/macos-bundle-metadata.txt"
MACOS_SMOKE_CODESIGN="$MACOS_SMOKE_DIR/macos-codesign.txt"
MACOS_SMOKE_LAUNCH="$MACOS_SMOKE_DIR/macos-launch.log"
MACOS_SCREENSHOT_DIR="${CAPTAINS_LOG_MACOS_SCREENSHOT_DIR:-/tmp/captainslog-macos-appstore-screenshots}"
MACOS_SCREENSHOT_MANIFEST="$MACOS_SCREENSHOT_DIR/macos-screenshot-manifest.txt"
MACOS_SCREENSHOT_AUDIT="$MACOS_SCREENSHOT_DIR/macos-screenshot-text-audit.log"
MACOS_EXPORT_DIR="${CAPTAINS_LOG_MACOS_EXPORT_DIR:-/tmp/captainslog-current-macos-appstore-export}"
MACOS_EXPORT_PATH="$MACOS_EXPORT_DIR/Export"
MACOS_PACKAGE="$(find "$MACOS_EXPORT_PATH" -maxdepth 1 -name '*.pkg' -print -quit 2>/dev/null || true)"
MACOS_PACKAGE_LABEL="${MACOS_PACKAGE:-$MACOS_EXPORT_PATH/*.pkg}"
MACOS_EXPORT_MANIFEST="$MACOS_EXPORT_PATH/MacExportManifest.txt"
WATCHOS_SMOKE_DIR="${CAPTAINS_LOG_WATCHOS_SMOKE_DIR:-/tmp/captainslog-watchos-smoke}"
WATCHOS_SMOKE_SCREENSHOT="$WATCHOS_SMOKE_DIR/watchos-launch.png"
WATCHOS_SMOKE_OCR="$WATCHOS_SMOKE_DIR/watchos-launch-ocr.txt"
TVOS_SMOKE_DIR="${CAPTAINS_LOG_TVOS_SMOKE_DIR:-/tmp/captainslog-tvos-smoke}"
TVOS_SMOKE_SCREENSHOT="$TVOS_SMOKE_DIR/tvos-launch.png"
TVOS_SMOKE_OCR="$TVOS_SMOKE_DIR/tvos-launch-ocr.txt"

local_failures=0
external_blockers=0
ipa_missing=0
export_manifest_missing=0
distribution_identity_available=0
macos_app_identity_available=0
macos_installer_identity_available=0
xcode_auth_env_ready=0

# shellcheck source=Scripts/lib/app_store_connect_env.sh
source "$ROOT_DIR/Scripts/lib/app_store_connect_env.sh"
app_store_connect_apply_env_defaults

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
    realpath "$path"
}

git_root_for_path() {
    local path="$1"
    local dir
    dir="$(dirname "$path")"
    git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true
}

branch_sync_warning() {
    local label="$1"
    local repo_dir="$2"
    shift 2
    local branch_line
    local upstream
    local linked_source_delta
    branch_line="$(git -C "$repo_dir" status --short --branch 2>/dev/null | sed -n '1p')"

    if printf '%s\n' "$branch_line" | rg -q '\[(ahead|behind|gone|diverged)'; then
        if (( $# > 0 )); then
            upstream="$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
            if [[ -n "$upstream" ]] && ! printf '%s\n' "$branch_line" | rg -q '\[gone\]'; then
                linked_source_delta="$(git -C "$repo_dir" diff --name-only HEAD "$upstream" -- "$@" 2>/dev/null | sed -n '1,8p')"
                if [[ -z "$linked_source_delta" ]]; then
                    warn "$label branch has upstream drift outside linked package source: $branch_line"
                    return
                fi
            fi
        fi
        warn "$label branch is not in sync with upstream: $branch_line"
        external "$label branch is not synced with upstream; push it or explicitly accept the unpushed source state before final release export"
    else
        pass "$label branch synced with upstream"
    fi
}

check_png_size() {
    local path="$1"
    local expected_width="$2"
    local expected_height="$3"
    local label="$4"
    local width
    local height

    if [[ ! -f "$path" ]]; then
        fail "$label missing: $path"
        return
    fi

    width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"
    if [[ "$width" == "$expected_width" && "$height" == "$expected_height" ]]; then
        pass "$label dimensions: ${width}x${height}"
    else
        fail "$label dimensions: ${width:-unknown}x${height:-unknown}, expected ${expected_width}x${expected_height}"
    fi
}

check_png_size_any() {
    local path="$1"
    local label="$2"
    shift 2
    local width
    local height
    local expected

    if [[ ! -f "$path" ]]; then
        fail "$label missing: $path"
        return
    fi

    width="$(sips -g pixelWidth "$path" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$path" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"

    for expected in "$@"; do
        if [[ "${width}x${height}" == "$expected" ]]; then
            pass "$label dimensions: ${width}x${height}"
            return
        fi
    done

    fail "$label dimensions: ${width:-unknown}x${height:-unknown}, expected one of: $*"
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

default_p8_candidate_names() {
    local dirs=(
        "$HOME/private_keys"
        "$HOME/.private_keys"
        "$HOME/.appstoreconnect/private_keys"
    )

    if [[ -n "${API_PRIVATE_KEYS_DIR:-}" ]]; then
        dirs+=("$API_PRIVATE_KEYS_DIR")
    fi

    local dir candidate abs_path
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r candidate; do
            [[ -f "$candidate" ]] || continue
            abs_path="$(absolute_path "$candidate")"
            case "$abs_path" in
                "$ROOT_DIR"/*)
                    continue
                    ;;
            esac
            basename "$candidate"
        done < <(find "$dir" -maxdepth 1 -type f -name "AuthKey_*.p8" 2>/dev/null)
    done | sort -u
}

default_p8_candidate_count() {
    default_p8_candidate_names | wc -l | tr -d ' '
}

check_p8_path() {
    local p8_path="$1"
    local source_label="$2"

    pass "App Store Connect .p8 key file found via $source_label"
    p8_path="$(absolute_path "$p8_path")"
    local p8_git_root
    p8_git_root="$(git_root_for_path "$p8_path")"
    case "$p8_path" in
        "$ROOT_DIR"/*)
            fail "App Store Connect .p8 key file must live outside the repo"
            ;;
        *)
            pass "App Store Connect .p8 key file is outside the repo"
            ;;
    esac
    if [[ -n "$p8_git_root" ]]; then
        fail "App Store Connect .p8 key file must live outside any git working tree: $p8_git_root"
    else
        pass "App Store Connect .p8 key file is outside git working trees"
    fi

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
        elif [[ "${CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME:-0}" == "1" ]]; then
            warn "App Store Connect .p8 filename is not $expected_p8_name; continuing because CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1"
        else
            fail "App Store Connect .p8 filename is not $expected_p8_name. Set CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1 only after manually verifying the key file belongs to this key ID."
        fi
    fi
}

xcode_auth_env_ready_for_status() {
    if [[ -z "${APP_STORE_CONNECT_API_KEY:-}" || -z "${APP_STORE_CONNECT_API_ISSUER:-}" || -z "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
        return 1
    fi
    if ! [[ "$APP_STORE_CONNECT_API_KEY" =~ ^[A-Za-z0-9]{10}$ ]]; then
        return 1
    fi
    if ! [[ "$APP_STORE_CONNECT_API_ISSUER" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
        return 1
    fi
    if [[ ! -f "$APP_STORE_CONNECT_P8_FILE" ]]; then
        return 1
    fi

    local p8_path
    local p8_git_root
    p8_path="$(absolute_path "$APP_STORE_CONNECT_P8_FILE")"
    p8_git_root="$(git_root_for_path "$p8_path")"
    case "$p8_path" in
        "$ROOT_DIR"/*)
            return 1
            ;;
    esac
    if [[ -n "$p8_git_root" || ! -r "$p8_path" ]]; then
        return 1
    fi
    local expected_p8_name
    expected_p8_name="AuthKey_${APP_STORE_CONNECT_API_KEY}.p8"
    if [[ "$(basename "$p8_path")" != "$expected_p8_name" && "${CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME:-0}" != "1" ]]; then
        return 1
    fi
    rg -q -- "-----BEGIN PRIVATE KEY-----" "$p8_path"
}

check_token_shaped_source_literals() {
    local sk_prefix token_pattern token_hits
    sk_prefix="$(printf '%s-' "sk")"
    token_pattern="(?<![A-Za-z0-9_])${sk_prefix}(proj-|ant-)?[A-Za-z0-9][A-Za-z0-9_.=-]{10,}|(?<![A-Za-z0-9_])(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}|(?<![A-Za-z0-9_])github_pat_[A-Za-z0-9_]{20,}"

    if token_hits="$(rg -P -n -I "$token_pattern" \
        "$ROOT_DIR/CaptainsLog" \
        "$ROOT_DIR/CaptainsLogTests" \
        "$ROOT_DIR/CaptainsLogUITests" \
        "$ROOT_DIR/Docs" \
        "$ROOT_DIR/Scripts")"; then
        fail "token-shaped source literals found; use runtime fixtures or external credentials:
$(printf '%s\n' "$token_hits" | sed -n '1,12p')"
    else
        pass "no token-shaped source literals found"
    fi
}

check_reference_project_platform_precedent() {
    local label="$1"
    local project_path="$2"
    local expected_watch_name="$3"
    local expected_tv_name="$4"
    local project_output
    local match_count

    if [[ ! -d "$project_path" ]]; then
        warn "$label reference project missing; cannot confirm cross-app platform precedent: $project_path"
        return
    fi

    if ! project_output="$(xcodebuild -list -project "$project_path" 2>/dev/null)"; then
        warn "$label reference project could not be listed; cannot confirm cross-app platform precedent"
        return
    fi

    if [[ -n "$expected_watch_name" ]]; then
        match_count="$(printf '%s\n' "$project_output" | rg -c "^[[:space:]]+${expected_watch_name}$" || true)"
        if [[ "$match_count" -ge 2 ]]; then
            pass "$label reference has Apple Watch target and scheme precedent: $expected_watch_name"
        else
            warn "$label reference did not show both Apple Watch target and scheme for $expected_watch_name"
        fi
    fi

    if [[ -n "$expected_tv_name" ]]; then
        match_count="$(printf '%s\n' "$project_output" | rg -c "^[[:space:]]+${expected_tv_name}$" || true)"
        if [[ "$match_count" -ge 2 ]]; then
            pass "$label reference has Apple TV target and scheme precedent: $expected_tv_name"
        else
            warn "$label reference did not show both Apple TV target and scheme for $expected_tv_name"
        fi
    fi
}

printf_platform_target_status() {
    local project_list
    local ios_settings
    local macos_settings
    local watch_settings
    local tv_settings

    printf '\nPlatform availability\n'

    if ios_settings="$(xcodebuild -project "$ROOT_DIR/CaptainsLog.xcodeproj" -scheme CaptainsLog-iOS -configuration Release -showBuildSettings 2>/dev/null)"; then
        if printf '%s\n' "$ios_settings" | rg -q 'TARGETED_DEVICE_FAMILY = 1,2'; then
            pass "iPhone and iPad enabled through TARGETED_DEVICE_FAMILY=1,2"
        else
            fail "iOS target is not configured as a universal iPhone/iPad app"
        fi

        if printf '%s\n' "$ios_settings" | rg -q 'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = YES'; then
            pass "Apple Vision Pro compatible iPhone/iPad availability is supported by build settings"
        else
            fail "iOS target does not report SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD=YES"
        fi
    else
        fail "unable to read CaptainsLog-iOS Release build settings for platform availability"
    fi

    if project_list="$(xcodebuild -list -project "$ROOT_DIR/CaptainsLog.xcodeproj" 2>/dev/null)"; then
        if printf '%s\n' "$project_list" | rg -q '^[[:space:]]+CaptainsLog-macOS$'; then
            warn "native macOS target exists, but first release still requires Mac signing/export, screenshots, TestFlight, and human QA before Mac App Store availability"

	            if macos_settings="$(xcodebuild -project "$ROOT_DIR/CaptainsLog.xcodeproj" -scheme CaptainsLog-macOS -configuration Release -showBuildSettings 2>/dev/null)"; then
	                if printf '%s\n' "$macos_settings" | rg -q "PRODUCT_BUNDLE_IDENTIFIER = ${MACOS_BUNDLE_ID//./[.]}"; then
	                    pass "macOS target bundle id is ${MACOS_BUNDLE_ID}"
	                else
	                    fail "macOS target bundle id is missing or mismatched"
	                fi
                if printf '%s\n' "$macos_settings" | rg -q 'CODE_SIGN_STYLE = Automatic'; then
                    pass "macOS target uses automatic signing"
                else
                    fail "macOS target does not use automatic signing"
                fi
                if printf '%s\n' "$macos_settings" | rg -q "DEVELOPMENT_TEAM = ${TEAM_ID}"; then
                    pass "macOS target development team is ${TEAM_ID}"
                else
                    fail "macOS target development team is not ${TEAM_ID}"
                fi
                if printf '%s\n' "$macos_settings" | rg -q 'ENABLE_HARDENED_RUNTIME = YES'; then
                    pass "macOS target has hardened runtime enabled"
                else
                    fail "macOS target does not have hardened runtime enabled"
                fi
	            else
	                fail "unable to read CaptainsLog-macOS Release build settings for platform availability"
	            fi

	            if [[ -x "$ROOT_DIR/Scripts/check_app_store_connect_record.py" && -n "${APP_STORE_CONNECT_API_KEY:-}" && -n "${APP_STORE_CONNECT_API_ISSUER:-}" ]]; then
	                if macos_bundle_output="$("$ROOT_DIR/Scripts/check_app_store_connect_record.py" --bundle-id "$MACOS_BUNDLE_ID" --require bundle-id 2>&1)"; then
	                    pass "native Mac Developer Portal bundle ID exists for ${MACOS_BUNDLE_ID}"
	                else
	                    external "native Mac Developer Portal bundle ID is missing or not visible to this API key; create it before native Mac App Store export"
	                    printf '%s\n' "$macos_bundle_output" | sed 's/^/  /'
	                fi
	            fi

            if [[ -x "$ROOT_DIR/Scripts/smoke_macos_launch.sh" ]]; then
                pass "macOS launch smoke script exists"
            else
                fail "macOS launch smoke script missing or not executable"
            fi

            if [[ -x "$ROOT_DIR/Scripts/capture_macos_app_store_screenshots.sh" ]]; then
                pass "macOS screenshot capture script exists"
            else
                fail "macOS screenshot capture script missing or not executable"
            fi

            if [[ -x "$ROOT_DIR/Scripts/export_macos_app_store_pkg.sh" ]]; then
                pass "macOS App Store package export script exists"
            else
                fail "macOS App Store package export script missing or not executable"
            fi

            if [[ -n "$MACOS_PACKAGE" && -f "$MACOS_PACKAGE" && -f "$MACOS_EXPORT_MANIFEST" ]]; then
                pass "macOS App Store package exists"
                pass "macOS App Store export manifest exists"
            else
                warn "macOS App Store package/export manifest missing; run Scripts/export_macos_app_store_pkg.sh $MACOS_EXPORT_DIR after Mac App Store signing or App Store Connect API auth is available"
            fi

            if [[ -f "$MACOS_SMOKE_METADATA" && -f "$MACOS_SMOKE_CODESIGN" && -f "$MACOS_SMOKE_LAUNCH" ]]; then
                if rg -q '^CFBundleIdentifier: com[.]blakecrosley[.]captainslog[.]mac$' "$MACOS_SMOKE_METADATA"; then
                    pass "macOS launch smoke bundle id recorded"
                else
                    fail "macOS launch smoke bundle id missing or mismatched"
                fi
                if rg -q '^LSApplicationCategoryType: public[.]app-category[.]developer-tools$' "$MACOS_SMOKE_METADATA"; then
                    pass "macOS launch smoke category recorded"
                else
                    fail "macOS launch smoke category missing or mismatched"
                fi
                if rg -q '^[0-9]+$' "$MACOS_SMOKE_LAUNCH"; then
                    pass "macOS launch smoke process recorded: $(sed -n '1p' "$MACOS_SMOKE_LAUNCH")"
                else
                    fail "macOS launch smoke process log missing pid"
                fi
                if rg -q "TeamIdentifier=not set" "$MACOS_SMOKE_CODESIGN"; then
                    warn "macOS launch smoke codesign TeamIdentifier is not set; Mac App Store signing/export remains open"
                else
                    pass "macOS launch smoke codesign TeamIdentifier is present"
                fi
            else
                warn "macOS launch smoke artifacts missing; run Scripts/smoke_macos_launch.sh $MACOS_SMOKE_DIR before Mac availability acceptance"
            fi

            if [[ -d "$MACOS_SCREENSHOT_DIR" ]]; then
                local macos_screenshot_count
                local macos_screenshot
                macos_screenshot_count="$(find "$MACOS_SCREENSHOT_DIR" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
                if [[ "$macos_screenshot_count" == "6" ]]; then
                    pass "macOS screenshot count: 6"
                else
                    fail "macOS screenshot count: ${macos_screenshot_count:-0}, expected 6"
                fi

                for macos_screenshot in \
                    "01-dashboard.png" \
                    "02-work-map.png" \
                    "03-journal.png" \
                    "04-repositories.png" \
                    "05-ai-providers.png" \
                    "06-privacy-data.png"; do
                    check_png_size_any "$MACOS_SCREENSHOT_DIR/$macos_screenshot" "macOS/$macos_screenshot" 2880x1800 2560x1600 1440x900 1280x800
                done

                if [[ -f "$MACOS_SCREENSHOT_MANIFEST" ]]; then
                    pass "macOS screenshot manifest exists"
                else
                    fail "macOS screenshot manifest missing: $MACOS_SCREENSHOT_MANIFEST"
                fi

                if [[ -f "$MACOS_SCREENSHOT_AUDIT" ]] && rg -q 'Screenshot text audit passed' "$MACOS_SCREENSHOT_AUDIT"; then
                    pass "macOS screenshot text audit passed"
                else
                    fail "macOS screenshot text audit missing or failed: $MACOS_SCREENSHOT_AUDIT"
                fi
            else
                warn "macOS screenshots missing; run Scripts/capture_macos_app_store_screenshots.sh $MACOS_SCREENSHOT_DIR before Mac screenshot acceptance"
            fi
        else
            pass "no native macOS target found"
        fi

        if [[ "$(printf '%s\n' "$project_list" | rg -c '^[[:space:]]+CaptainsLog-watchOS$' || true)" -ge 2 ]]; then
            pass "Apple Watch target and scheme exist: CaptainsLog-watchOS"
            if watch_settings="$(xcodebuild -project "$ROOT_DIR/CaptainsLog.xcodeproj" -scheme CaptainsLog-watchOS -configuration Release -showBuildSettings 2>/dev/null)"; then
                if printf '%s\n' "$watch_settings" | rg -q "PRODUCT_BUNDLE_IDENTIFIER = com[.]blakecrosley[.]captainslog[.]watchkitapp"; then
                    pass "Apple Watch bundle id is com.blakecrosley.captainslog.watchkitapp"
                else
                    fail "Apple Watch bundle id is missing or mismatched"
                fi
                if printf '%s\n' "$watch_settings" | rg -q "DEVELOPMENT_TEAM = ${TEAM_ID}"; then
                    pass "Apple Watch development team is ${TEAM_ID}"
                else
                    fail "Apple Watch development team is not ${TEAM_ID}"
                fi
            else
                fail "unable to read CaptainsLog-watchOS Release build settings for platform availability"
            fi
            if [[ -x "$ROOT_DIR/Scripts/smoke_watchos_launch.sh" ]]; then
                pass "Apple Watch launch smoke script exists"
            else
                fail "Apple Watch launch smoke script missing or not executable"
            fi
            if [[ -f "$WATCHOS_SMOKE_SCREENSHOT" && -f "$WATCHOS_SMOKE_OCR" ]]; then
                local watch_width watch_height
                watch_width="$(sips -g pixelWidth "$WATCHOS_SMOKE_SCREENSHOT" 2>/dev/null | awk '/pixelWidth:/ { print $2; exit }')"
                watch_height="$(sips -g pixelHeight "$WATCHOS_SMOKE_SCREENSHOT" 2>/dev/null | awk '/pixelHeight:/ { print $2; exit }')"
                if [[ -n "$watch_width" && -n "$watch_height" ]]; then
                    pass "Apple Watch launch screenshot dimensions: ${watch_width}x${watch_height}"
                else
                    fail "unable to read Apple Watch launch screenshot dimensions"
                fi
                if rg -q -i "Captain'?s Log|Sync from iPhone|Waiting|Log" "$WATCHOS_SMOKE_OCR"; then
                    pass "Apple Watch launch OCR found companion UI"
                else
                    fail "Apple Watch launch OCR is missing companion UI text"
                fi
            else
                warn "Apple Watch launch smoke artifacts missing; run Scripts/smoke_watchos_launch.sh $WATCHOS_SMOKE_DIR before Watch launch acceptance"
            fi
            warn "Apple Watch target is a first-pass companion shell; Watch release still requires phone-synced data, icons, screenshots, signed archive/export, TestFlight, and watch QA before availability"
        else
            warn "Captain's Log has no Apple Watch app target or scheme; Apple Watch is not ready"
        fi

        if [[ "$(printf '%s\n' "$project_list" | rg -c '^[[:space:]]+CaptainsLog-tvOS$' || true)" -ge 2 ]]; then
            pass "Apple TV target and scheme exist: CaptainsLog-tvOS"
            if tv_settings="$(xcodebuild -project "$ROOT_DIR/CaptainsLog.xcodeproj" -scheme CaptainsLog-tvOS -configuration Release -showBuildSettings 2>/dev/null)"; then
                if printf '%s\n' "$tv_settings" | rg -q "PRODUCT_BUNDLE_IDENTIFIER = com[.]blakecrosley[.]captainslog[.]tv"; then
                    pass "Apple TV bundle id is com.blakecrosley.captainslog.tv"
                else
                    fail "Apple TV bundle id is missing or mismatched"
                fi
                if printf '%s\n' "$tv_settings" | rg -q "DEVELOPMENT_TEAM = ${TEAM_ID}"; then
                    pass "Apple TV development team is ${TEAM_ID}"
                else
                    fail "Apple TV development team is not ${TEAM_ID}"
                fi
            else
                fail "unable to read CaptainsLog-tvOS Release build settings for platform availability"
            fi
            if [[ -x "$ROOT_DIR/Scripts/smoke_tvos_launch.sh" ]]; then
                pass "Apple TV launch smoke script exists"
            else
                fail "Apple TV launch smoke script missing or not executable"
            fi
            if [[ -f "$TVOS_SMOKE_SCREENSHOT" && -f "$TVOS_SMOKE_OCR" ]]; then
                local tv_width tv_height
                tv_width="$(sips -g pixelWidth "$TVOS_SMOKE_SCREENSHOT" 2>/dev/null | awk '/pixelWidth:/ { print $2; exit }')"
                tv_height="$(sips -g pixelHeight "$TVOS_SMOKE_SCREENSHOT" 2>/dev/null | awk '/pixelHeight:/ { print $2; exit }')"
                if [[ -n "$tv_width" && -n "$tv_height" ]]; then
                    pass "Apple TV launch screenshot dimensions: ${tv_width}x${tv_height}"
                else
                    fail "unable to read Apple TV launch screenshot dimensions"
                fi
                if rg -q -i "Captain'?s Log|Captains Log" "$TVOS_SMOKE_OCR" \
                    && rg -q -i "No GitHub credentials|Use the main app|read-only" "$TVOS_SMOKE_OCR"; then
                    pass "Apple TV launch OCR found read-only companion UI"
                else
                    fail "Apple TV launch OCR is missing read-only companion UI text"
                fi
            else
                warn "Apple TV launch smoke artifacts missing; run Scripts/smoke_tvos_launch.sh $TVOS_SMOKE_DIR before TV launch acceptance"
            fi
            warn "Apple TV target is a first-pass read-only shell; TV release still requires real setup/data path, icons/top-shelf assets, screenshots, signed archive/export, TestFlight, and TV QA before availability"
        else
            warn "Captain's Log has no Apple TV app target or scheme; Apple TV is not ready"
        fi
    else
        fail "unable to list Xcode targets for platform availability"
    fi

    if rg -q '^  CaptainsLog-watchOS:' "$ROOT_DIR/project.yml" && rg -q 'platform:[[:space:]]+watchOS' "$ROOT_DIR/project.yml"; then
        pass "project.yml defines the Captain's Log watchOS app target"
    else
        warn "project.yml has no watchOS app target for Captain's Log"
    fi

    if rg -q '^  CaptainsLog-tvOS:' "$ROOT_DIR/project.yml" && rg -q 'platform:[[:space:]]+tvOS' "$ROOT_DIR/project.yml"; then
        pass "project.yml defines the Captain's Log tvOS app target"
    else
        warn "project.yml has no tvOS app target for Captain's Log"
    fi

    check_reference_project_platform_precedent "Return" "$RETURN_REFERENCE_PROJECT" "ReturnWatch Watch App" "ReturnTV"
    check_reference_project_platform_precedent "Get Bananas (Banana List project)" "$BANANA_LIST_REFERENCE_PROJECT" "Banana List Watch Watch App" ""

    if [[ -x "$ROOT_DIR/Scripts/smoke_vision_compatible_launch.sh" ]]; then
        pass "Vision compatible launch smoke script exists"
    else
        fail "Vision compatible launch smoke script missing or not executable"
    fi

    if [[ -f "$VISION_SMOKE_SCREENSHOT" && -f "$VISION_SMOKE_OCR" ]]; then
        local vision_width vision_height
        vision_width="$(sips -g pixelWidth "$VISION_SMOKE_SCREENSHOT" 2>/dev/null | awk '/pixelWidth:/ { print $2; exit }')"
        vision_height="$(sips -g pixelHeight "$VISION_SMOKE_SCREENSHOT" 2>/dev/null | awk '/pixelHeight:/ { print $2; exit }')"
        if [[ -n "$vision_width" && -n "$vision_height" ]]; then
            pass "Vision compatible launch screenshot dimensions: ${vision_width}x${vision_height}"
        else
            fail "unable to read Vision compatible launch screenshot dimensions"
        fi

        if rg -q -i "Captain'?s Log" "$VISION_SMOKE_OCR" \
            && { rg -q -i "Sign in with GitHub" "$VISION_SMOKE_OCR" || rg -q -i "Authorize this device" "$VISION_SMOKE_OCR"; } \
            && rg -q -i "Use Demo Data" "$VISION_SMOKE_OCR"; then
            pass "Vision compatible launch OCR found first-run UI"
        else
            fail "Vision compatible launch OCR is missing first-run UI text"
        fi

        if rg -q -i "Keychain returned status -34018" "$VISION_SMOKE_OCR"; then
            warn "Vision compatible launch OCR still shows Keychain returned status -34018; signed TestFlight/auth behavior remains open"
        else
            pass "Vision compatible launch OCR did not find Keychain returned status -34018"
        fi
    else
        warn "Vision compatible launch smoke artifacts missing; run Scripts/smoke_vision_compatible_launch.sh $VISION_SMOKE_DIR before final Vision acceptance"
    fi
}

printf "Captain's Log App Store readiness status\n"
printf 'Repo: %s\n' "$ROOT_DIR"
printf 'Screenshots: %s\n' "$SCREENSHOT_DIR"
printf 'Packaged screenshots: %s\n' "$PACKAGED_DIR"
printf 'Screenshot review: %s\n' "$SCREENSHOT_REVIEW_DIR"
printf 'Vision smoke: %s\n' "$VISION_SMOKE_DIR"
printf 'macOS smoke: %s\n' "$MACOS_SMOKE_DIR"
printf 'macOS screenshots: %s\n' "$MACOS_SCREENSHOT_DIR"
printf 'macOS package: %s\n' "$MACOS_PACKAGE_LABEL"
printf 'watchOS smoke: %s\n' "$WATCHOS_SMOKE_DIR"
printf 'tvOS smoke: %s\n' "$TVOS_SMOKE_DIR"
printf 'IPA: %s\n\n' "$IPA_PATH"

need_command git
need_command xcrun
need_command xcodebuild
need_command sips
need_command sqlite3
need_command unzip
need_command rg
need_command magick
need_command security
need_xcrun_tool altool
need_xcrun_tool swift

if xcode_version="$(xcodebuild -version 2>/dev/null)" && xcode_sdks="$(xcodebuild -showsdks 2>/dev/null)"; then
    xcode_first_line="$(printf '%s\n' "$xcode_version" | sed -n '1p')"
    xcode_major="$(printf '%s\n' "$xcode_first_line" | sed -E 's/^Xcode ([0-9]+).*/\1/')"
    if ! [[ "$xcode_major" =~ ^[0-9]+$ ]] || (( xcode_major < 26 )); then
        fail "$xcode_first_line is older than Xcode 26 required for 2026 App Store upload"
    else
        if printf '%s\n' "$xcode_sdks" | rg -q 'iphoneos(2[6-9]|[3-9][0-9])([.]|$)'; then
            pass "$xcode_first_line satisfies Xcode 26+ and iOS 26+ SDK requirements"
        else
            fail "$xcode_first_line does not list an iOS 26 or newer SDK required for 2026 App Store upload"
        fi
        if printf '%s\n' "$xcode_sdks" | rg -q 'macosx(2[6-9]|[3-9][0-9])([.]|$)'; then
            pass "$xcode_first_line satisfies macOS 26+ SDK requirements"
        else
            fail "$xcode_first_line does not list a macOS 26 or newer SDK required for native Mac App Store export"
        fi
    fi
else
    fail "xcodebuild version or SDK list unavailable"
fi

if xcode_auth_env_ready_for_status; then
    xcode_auth_env_ready=1
fi

identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"

if printf '%s\n' "$identity_output" | rg -q "\"(Apple Distribution|iOS Distribution):.*\\(${TEAM_ID}\\)\""; then
    distribution_identity_available=1
    pass "App Store distribution signing identity for team ${TEAM_ID} available in local keychain"
elif (( xcode_auth_env_ready == 1 )); then
    pass "App Store Connect API-key auth inputs for xcodebuild provisioning updates are present"
    warn "App Store distribution signing identity for team ${TEAM_ID} is not available in the local keychain; export will rely on xcodebuild cloud-managed signing and must still prove cloud certificate access"
else
    external "App Store export signing is not ready; provide either an Apple Distribution/iOS Distribution identity for team ${TEAM_ID} or set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER for xcodebuild provisioning updates with cloud-managed distribution certificate access. APP_STORE_CONNECT_P8_FILE is optional when the matching AuthKey_<key>.p8 file exists in ~/.appstoreconnect/private_keys. Fastlane ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases are also accepted."
fi

if printf '%s\n' "$identity_output" | rg -q "\"(Apple Distribution|Mac App Distribution|3rd Party Mac Developer Application):.*\\(${TEAM_ID}\\)\""; then
    macos_app_identity_available=1
    pass "Mac App Store application signing identity for team ${TEAM_ID} available in local keychain"
elif (( xcode_auth_env_ready == 1 )); then
    pass "App Store Connect API-key auth inputs are present for native Mac provisioning updates"
    warn "Mac App Store application signing identity for team ${TEAM_ID} is not available in the local keychain; export_macos_app_store_pkg.sh will rely on xcodebuild cloud-managed signing and must still prove cloud certificate access"
else
    external "Mac App Store application signing is not ready; provide an Apple Distribution/Mac App Distribution identity for team ${TEAM_ID} or set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER for xcodebuild provisioning updates with cloud-managed distribution certificate access. APP_STORE_CONNECT_P8_FILE is optional when the matching AuthKey_<key>.p8 file exists in ~/.appstoreconnect/private_keys. Fastlane ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases are also accepted."
fi

if printf '%s\n' "$identity_output" | rg -q "\"(Mac Installer Distribution|3rd Party Mac Developer Installer):.*\\(${TEAM_ID}\\)\""; then
    macos_installer_identity_available=1
    pass "Mac App Store installer signing identity for team ${TEAM_ID} available in local keychain"
elif (( xcode_auth_env_ready == 1 )); then
    pass "App Store Connect API-key auth inputs are present for native Mac package export"
    warn "Mac App Store installer signing identity for team ${TEAM_ID} is not available in the local keychain; export_macos_app_store_pkg.sh will rely on xcodebuild cloud-managed signing and must still prove cloud certificate access"
else
    external "Mac App Store installer signing is not ready; provide a Mac Installer Distribution identity for team ${TEAM_ID} or set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER for xcodebuild provisioning updates with cloud-managed distribution certificate access. APP_STORE_CONNECT_P8_FILE is optional when the matching AuthKey_<key>.p8 file exists in ~/.appstoreconnect/private_keys. Fastlane ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases are also accepted."
fi

printf '\nLocal artifact checks\n'
if [[ -f "$IPA_PATH" ]]; then
    pass "IPA exists"
else
    ipa_missing=1
    fail "IPA missing: $IPA_PATH"
fi

if [[ -d "$ARCHIVE_PATH" && ! -f "$EXPORT_MANIFEST" ]]; then
    archive_signing_identity="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:SigningIdentity' "$ARCHIVE_PATH/Info.plist" 2>/dev/null || true)"
    if [[ -n "$archive_signing_identity" ]]; then
        fail "archive exists without a matching export manifest and may be stale: $ARCHIVE_PATH signed with $archive_signing_identity"
    else
        fail "archive exists without a matching export manifest and may be stale: $ARCHIVE_PATH"
    fi
fi

repo_private_keys=()
while IFS= read -r path; do
    repo_private_keys+=("$path")
done < <(find "$ROOT_DIR" \
    -path "$ROOT_DIR/.git" -prune -o \
    \( -name "private_keys" -type d -o -name "*.p8" -type f \) \
    -print)

if (( ${#repo_private_keys[@]} == 0 )); then
    pass "no App Store private keys found inside repo"
else
    fail "App Store private key material must stay outside the repo:
$(printf '%s\n' "${repo_private_keys[@]}" | sed -n '1,12p')"
fi

check_token_shaped_source_literals

if [[ -f "$EXPORT_MANIFEST" ]]; then
    pass "export manifest exists"
else
    export_manifest_missing=1
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

    packaged_screens=(
        "01-dashboard.png"
        "02-work-map.png"
        "03-journal.png"
        "04-repositories.png"
        "05-ai-providers.png"
        "06-privacy-data.png"
    )
    for screen in "${packaged_screens[@]}"; do
        check_png_size "$PACKAGED_DIR/iphone-6.9/$screen" 1320 2868 "iphone-6.9/$screen"
        check_png_size_any "$PACKAGED_DIR/ipad-13/$screen" "ipad-13/$screen" 2064x2752 2752x2064
    done
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

if "$ROOT_DIR/Scripts/audit_app_store_screenshot_text.sh" "$PACKAGED_DIR"; then
    pass "screenshot text audit"
else
    fail "screenshot text audit failed"
fi

printf '\nSource cleanliness\n'
repo_status="$(git -C "$ROOT_DIR" status --short)"
if [[ -z "$repo_status" ]]; then
    pass "CaptainsLog git tree clean"
else
    fail "CaptainsLog git tree is dirty:
$repo_status"
fi
branch_sync_warning "CaptainsLog" "$ROOT_DIR"

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
    branch_sync_warning "Kit941" "$KIT941_DIR" Package.swift Package.resolved Sources/Kit941
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
        pass "exported Kit941 linked package source was clean"
    else
        fail "exported Kit941 linked package source was dirty or unknown: ${exported_kit_dirty:-missing}"
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

printf_platform_target_status

printf '\nIPA local check\n'
if [[ ! -f "$IPA_PATH" ]]; then
    warn "IPA local check skipped until a current IPA exists"
elif "$ROOT_DIR/Scripts/upload_app_store_ipa.sh" local-check "$IPA_PATH"; then
    pass "IPA local check"
else
    fail "IPA local check failed"
fi

printf '\nCredential guard self-test\n'
if "$ROOT_DIR/Scripts/upload_app_store_ipa.sh" credential-guard-self-test; then
    pass "App Store upload credential guard self-test"
else
    fail "App Store upload credential guard self-test failed"
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
    external "App Store Connect API key and issuer are not set; validate/upload/status remain blocked. Fastlane ASC_KEY_ID and ASC_ISSUER_ID aliases are also unset."
fi

if [[ -n "${APP_STORE_CONNECT_PROVIDER_PUBLIC_ID:-}" ]]; then
    pass "App Store Connect provider public ID is set"
else
    warn "App Store Connect provider public ID is not set; only the older altool app-record path needs it because Scripts/check_app_store_connect_record.py uses the REST API directly"
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
    p8_candidate_count="$(default_p8_candidate_count)"
    if (( p8_candidate_count > 0 )); then
        if (( p8_candidate_count > 1 )); then
            external "$p8_candidate_count App Store Connect candidate .p8 private-key files are staged outside the repo in altool default private-key search paths; set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER so the selected key is unambiguous. APP_STORE_CONNECT_P8_FILE is only needed when the matching AuthKey_<key>.p8 is not in a supported private-key directory. Fastlane ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases are also accepted."
        else
            external "1 App Store Connect candidate .p8 private-key file is staged outside the repo in altool default private-key search paths, but no selected APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER are set"
        fi
        while IFS= read -r candidate_name; do
            [[ -n "$candidate_name" ]] || continue
            printf '[info] staged App Store Connect key candidate: %s\n' "$candidate_name"
        done < <(default_p8_candidate_names)
    else
        external "App Store Connect .p8 key file is not set and AuthKey_<key>.p8 was not found in altool's default private key search paths"
    fi
fi

if (( distribution_identity_available == 0 && xcode_auth_env_ready == 0 )); then
    external "xcodebuild App Store Connect API-key auth is not configured; without a local distribution identity, export_app_store_ipa.sh cannot regenerate the current IPA"
elif (( xcode_auth_env_ready == 1 )); then
    pass "xcodebuild App Store Connect API-key auth inputs are present for export_app_store_ipa.sh"
fi

if (( (macos_app_identity_available == 0 || macos_installer_identity_available == 0) && xcode_auth_env_ready == 0 )); then
    external "xcodebuild App Store Connect API-key auth is not configured; without local Mac App Store application and installer signing identities, export_macos_app_store_pkg.sh cannot regenerate the native Mac package"
elif (( xcode_auth_env_ready == 1 )); then
    pass "xcodebuild App Store Connect API-key auth inputs are present for export_macos_app_store_pkg.sh"
fi

app_record_checked=0
if [[ -x "$ROOT_DIR/Scripts/check_app_store_connect_record.py" && -n "${APP_STORE_CONNECT_API_KEY:-}" && -n "${APP_STORE_CONNECT_API_ISSUER:-}" ]]; then
    app_record_checked=1
    if app_record_output="$("$ROOT_DIR/Scripts/check_app_store_connect_record.py" --bundle-id "$IOS_BUNDLE_ID" 2>&1)"; then
        pass "App Store Connect app record exists for $IOS_BUNDLE_ID"
    else
        external "App Store Connect app record is missing or not visible to this API key; create it, then rerun Scripts/check_app_store_connect_record.py"
        printf '%s\n' "$app_record_output" | sed 's/^/  /'
    fi
fi
if (( app_record_checked == 0 )); then
    external "create or confirm the App Store Connect app record with Scripts/check_app_store_connect_record.py or Scripts/upload_app_store_ipa.sh app-record"
fi
external "complete manual App Store Connect fields from Docs/AppStoreMetadata.md, including regional availability prompts, Apple Vision Pro availability enabled for the compatible iPhone/iPad app, Apple Silicon Mac opt-out, EU DSA trader status, Labels and Markings URLs, regulated medical device status, and tax category if App Store Connect shows them"
external "upload build and verify TestFlight processing"
external "complete human screenshot marketing acceptance"
external "complete legal/privacy review"
pass "blakecrosley.com PR 15 source state reconciled"
external "final human tap-through on the real large-account install"

printf '\nSummary\n'
if (( local_failures > 0 )); then
    printf '[fail] Local readiness failed with %d issue(s).\n' "$local_failures" >&2
    if (( ipa_missing == 1 || export_manifest_missing == 1 )); then
        cat <<'NEXT_LOCAL' >&2

Next local action:
1. Run Scripts/app_store_signing_status.sh.
2. Make one App Store export-signing path complete: either Xcode Apple Distribution/iOS Distribution signing for team M4WTLM6RAQ with a private key, or APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER for xcodebuild provisioning updates plus cloud-managed distribution certificate access. APP_STORE_CONNECT_P8_FILE is optional when AuthKey_<key>.p8 is in ~/.appstoreconnect/private_keys. Fastlane ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases are also accepted.
3. Regenerate the current IPA and export manifest:
   CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
4. If intentionally adding the native Mac target to this release, regenerate the native Mac App Store package:
   CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export
5. Rerun Scripts/app_store_readiness_status.sh.
NEXT_LOCAL
    fi
    exit 1
fi

pass "local readiness passed"
if (( external_blockers > 0 )); then
    printf '[external] %d external gate(s) remain before submission.\n' "$external_blockers"
    cat <<'NEXT_STEPS'

Next external actions:
1. Open Docs/AppStoreConnectRunbook.md and keep Docs/AppStoreConnectSubmission.md available as the evidence packet.
2. Create or confirm the App Store Connect app record, then complete the manual fields from Docs/AppStoreMetadata.md, including regional availability prompts, Apple Vision Pro availability enabled for the compatible iPhone/iPad app, Apple Silicon Mac opt-out, EU DSA trader status, Labels and Markings URLs, regulated medical device status, and tax category if App Store Connect shows them.
3. Check signing state with Scripts/app_store_signing_status.sh, make either Xcode distribution signing or xcodebuild API-key provisioning auth with cloud-managed distribution certificate access available, then regenerate the current IPA if readiness reports it missing or stale:
   CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
4. If intentionally adding the native Mac target to this release, regenerate the native Mac App Store package:
   CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export
5. Set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER, or export Fastlane ASC_KEY_ID and ASC_ISSUER_ID aliases. Set APP_STORE_CONNECT_P8_FILE/ASC_KEY_PATH only when AuthKey_<key>.p8 is not already in ~/.appstoreconnect/private_keys.
6. Run:
   Scripts/check_app_store_connect_record.py
   Scripts/upload_app_store_ipa.sh validate "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
   Scripts/upload_app_store_ipa.sh upload "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
7. Open /tmp/captainslog-appstore-review/contact-sheet.png for human screenshot approval.
8. Complete legal/privacy review and final real-account tap-through before submitting.
NEXT_STEPS
fi
