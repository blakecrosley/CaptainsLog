#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="com.blakecrosley.captainslog"
DEFAULT_IPA="/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
COMMAND="${1:-local-check}"

if [[ $# -gt 0 ]]; then
    shift
fi

IPA_PATH="${1:-${CAPTAINS_LOG_IPA_PATH:-$DEFAULT_IPA}}"
ALTOOL_OUTPUT_FORMAT="${ALTOOL_OUTPUT_FORMAT:-normal}"
WAIT_FOR_PROCESSING="${APP_STORE_CONNECT_WAIT:-0}"

usage() {
    cat <<'USAGE'
Usage:
  Scripts/upload_app_store_ipa.sh local-check [ipa]
  Scripts/upload_app_store_ipa.sh validate [ipa]
  Scripts/upload_app_store_ipa.sh upload [ipa]
  Scripts/upload_app_store_ipa.sh status [ipa]

Authentication for validate/upload/status:
  APP_STORE_CONNECT_API_KEY       App Store Connect API key ID.
  APP_STORE_CONNECT_API_ISSUER    App Store Connect issuer UUID.

Optional:
  APP_STORE_CONNECT_P8_FILE       Direct path to AuthKey_<key>.p8.
  APP_STORE_CONNECT_PROVIDER_PUBLIC_ID
  APP_STORE_CONNECT_DELIVERY_ID   Use for status after upload.
  APP_STORE_CONNECT_APPLE_ID      App Apple ID for status when delivery ID is unavailable.
  APP_STORE_CONNECT_WAIT=1        Wait for upload/status processing.
  ALTOOL_OUTPUT_FORMAT=json       Use altool JSON output.
USAGE
}

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

extract_app() {
    local ipa_path="$1"
    local temp_dir="$2"

    unzip -q "$ipa_path" -d "$temp_dir"
    find "$temp_dir/Payload" -maxdepth 1 -name "*.app" -print -quit
}

local_check() {
    local ipa_path="$1"

    [[ -f "$ipa_path" ]] || fail "IPA not found: $ipa_path"

    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' RETURN

    local app_path
    app_path="$(extract_app "$ipa_path" "$temp_dir")"
    [[ -n "$app_path" && -d "$app_path" ]] || fail "App bundle not found in IPA"

    local info_plist="$app_path/Info.plist"
    local privacy_manifest="$app_path/PrivacyInfo.xcprivacy"
    local export_manifest
    export_manifest="$(dirname "$ipa_path")/ExportManifest.txt"
    [[ -f "$info_plist" ]] || fail "Info.plist missing from IPA app"
    [[ -f "$privacy_manifest" ]] || fail "PrivacyInfo.xcprivacy missing from IPA app"

    local bundle_id version build encryption get_task_allow
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
    build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
    encryption="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info_plist")"
    get_task_allow="$(codesign -d --entitlements :- "$app_path" 2>/dev/null | plutil -extract get-task-allow raw -o - - 2>/dev/null || true)"

    [[ "$bundle_id" == "$BUNDLE_ID" ]] || fail "Unexpected bundle id: $bundle_id"
    [[ "$encryption" == "false" ]] || fail "Unexpected ITSAppUsesNonExemptEncryption=$encryption"
    [[ "$get_task_allow" == "false" ]] || fail "Expected get-task-allow=false, got ${get_task_allow:-missing}"

    local exported_commit git_dirty
    if [[ -f "$export_manifest" ]]; then
        exported_commit="$(awk -F ': ' '/^Exported app commit:/ { print $2; exit }' "$export_manifest")"
        git_dirty="$(awk -F ': ' '/^Git dirty at export:/ { print $2; exit }' "$export_manifest")"
    else
        exported_commit=""
        git_dirty=""
    fi

    printf 'IPA local check passed\n'
    printf 'IPA: %s\n' "$ipa_path"
    if [[ -f "$export_manifest" ]]; then
        printf 'Export manifest: present\n'
        [[ -n "$exported_commit" ]] && printf 'Exported app commit: %s\n' "$exported_commit"
        [[ -n "$git_dirty" ]] && printf 'Git dirty at export: %s\n' "$git_dirty"
    else
        printf 'Export manifest: missing\n'
    fi
    printf 'Bundle: %s\n' "$bundle_id"
    printf 'Version: %s (%s)\n' "$version" "$build"
    printf 'Privacy manifest: present\n'
    printf 'Non-exempt encryption: %s\n' "$encryption"
    printf 'get-task-allow: %s\n' "$get_task_allow"
}

auth_args=()

build_auth_args() {
    if [[ -n "${APP_STORE_CONNECT_API_KEY:-}" && -n "${APP_STORE_CONNECT_API_ISSUER:-}" ]]; then
        auth_args=(
            --api-key "$APP_STORE_CONNECT_API_KEY"
            --api-issuer "$APP_STORE_CONNECT_API_ISSUER"
        )
        if [[ -n "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
            auth_args+=(--p8-file-path "$APP_STORE_CONNECT_P8_FILE")
        fi
    elif [[ -n "${APP_STORE_CONNECT_USERNAME:-}" && -n "${APP_STORE_CONNECT_PASSWORD:-}" ]]; then
        auth_args=(
            --username "$APP_STORE_CONNECT_USERNAME"
            --password "$APP_STORE_CONNECT_PASSWORD"
        )
    else
        fail "Set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER before using $COMMAND"
    fi

    if [[ -n "${APP_STORE_CONNECT_PROVIDER_PUBLIC_ID:-}" ]]; then
        auth_args+=(--provider-public-id "$APP_STORE_CONNECT_PROVIDER_PUBLIC_ID")
    fi
}

ipa_version() {
    local field="$1"
    local ipa_path="$2"
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' RETURN

    local app_path
    app_path="$(extract_app "$ipa_path" "$temp_dir")"
    /usr/libexec/PlistBuddy -c "Print :$field" "$app_path/Info.plist"
}

run_validate() {
    local_check "$IPA_PATH"
    build_auth_args
    xcrun altool \
        --validate-app "$IPA_PATH" \
        "${auth_args[@]}" \
        --output-format "$ALTOOL_OUTPUT_FORMAT"
}

run_upload() {
    local_check "$IPA_PATH"
    build_auth_args

    local args=(
        --upload-package "$IPA_PATH"
        "${auth_args[@]}"
        --show-progress
        --output-format "$ALTOOL_OUTPUT_FORMAT"
    )

    if [[ "$WAIT_FOR_PROCESSING" == "1" ]]; then
        args+=(--wait)
    fi

    xcrun altool "${args[@]}"
}

run_status() {
    build_auth_args

    local args=(--build-status "${auth_args[@]}" --output-format "$ALTOOL_OUTPUT_FORMAT")
    if [[ -n "${APP_STORE_CONNECT_DELIVERY_ID:-}" ]]; then
        args+=(--delivery-id "$APP_STORE_CONNECT_DELIVERY_ID")
    else
        [[ -n "${APP_STORE_CONNECT_APPLE_ID:-}" ]] || fail "Set APP_STORE_CONNECT_DELIVERY_ID or APP_STORE_CONNECT_APPLE_ID for status"
        local build version
        build="${CAPTAINS_LOG_BUILD_NUMBER:-$(ipa_version CFBundleVersion "$IPA_PATH")}"
        version="${CAPTAINS_LOG_MARKETING_VERSION:-$(ipa_version CFBundleShortVersionString "$IPA_PATH")}"
        args+=(
            --apple-id "$APP_STORE_CONNECT_APPLE_ID"
            --bundle-version "$build"
            --bundle-short-version-string "$version"
            --platform ios
        )
    fi

    if [[ "$WAIT_FOR_PROCESSING" == "1" ]]; then
        args+=(--wait)
    fi

    xcrun altool "${args[@]}"
}

case "$COMMAND" in
    local-check)
        local_check "$IPA_PATH"
        ;;
    validate)
        run_validate
        ;;
    upload)
        run_upload
        ;;
    status)
        run_status
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        fail "Unknown command: $COMMAND"
        ;;
esac
