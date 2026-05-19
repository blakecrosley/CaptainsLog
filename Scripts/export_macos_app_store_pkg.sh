#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CaptainsLog.xcodeproj"
SCHEME="CaptainsLog-macOS"
TEAM_ID="M4WTLM6RAQ"
BUNDLE_ID="com.blakecrosley.captainslog.mac"
OUTPUT_DIR="${1:-/tmp/captainslog-current-macos-appstore-export}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$OUTPUT_DIR/CaptainsLog-macOS.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$OUTPUT_DIR/Export}"
EXPORT_MANIFEST="$EXPORT_PATH/MacExportManifest.txt"
KIT941_DIR="$ROOT_DIR/../941Kit"
xcode_auth_args=()

# shellcheck source=Scripts/lib/app_store_connect_env.sh
source "$ROOT_DIR/Scripts/lib/app_store_connect_env.sh"

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

configure_xcode_auth_args() {
    local has_any_auth_value=0
    app_store_connect_apply_fastlane_aliases

    if [[ -n "${APP_STORE_CONNECT_API_KEY:-}" || -n "${APP_STORE_CONNECT_API_ISSUER:-}" || -n "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
        has_any_auth_value=1
    fi

    if (( has_any_auth_value == 0 )); then
        return
    fi

    if [[ -z "${APP_STORE_CONNECT_API_KEY:-}" || -z "${APP_STORE_CONNECT_API_ISSUER:-}" || -z "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
        app_store_connect_auth_env_hint >&2
        exit 1
    fi

    if ! [[ "$APP_STORE_CONNECT_API_KEY" =~ ^[A-Za-z0-9]{10}$ ]]; then
        printf 'APP_STORE_CONNECT_API_KEY should be a 10-character key ID.\n' >&2
        exit 1
    fi

    if ! [[ "$APP_STORE_CONNECT_API_ISSUER" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
        printf 'APP_STORE_CONNECT_API_ISSUER should be a UUID.\n' >&2
        exit 1
    fi

    if [[ ! -f "$APP_STORE_CONNECT_P8_FILE" ]]; then
        printf 'APP_STORE_CONNECT_P8_FILE does not exist: %s\n' "$APP_STORE_CONNECT_P8_FILE" >&2
        exit 1
    fi

    APP_STORE_CONNECT_P8_FILE="$(absolute_path "$APP_STORE_CONNECT_P8_FILE")"
    local p8_git_root
    p8_git_root="$(git_root_for_path "$APP_STORE_CONNECT_P8_FILE")"
    case "$APP_STORE_CONNECT_P8_FILE" in
        "$ROOT_DIR"/*)
            printf 'App Store Connect .p8 key file must live outside this repo: %s\n' "$APP_STORE_CONNECT_P8_FILE" >&2
            exit 1
            ;;
    esac
    if [[ -n "$p8_git_root" ]]; then
        printf 'App Store Connect .p8 key file must live outside any git working tree: %s\n' "$p8_git_root" >&2
        exit 1
    fi
    if [[ ! -r "$APP_STORE_CONNECT_P8_FILE" ]]; then
        printf 'App Store Connect .p8 key file is not readable: %s\n' "$APP_STORE_CONNECT_P8_FILE" >&2
        exit 1
    fi
    if ! rg -q -- "-----BEGIN PRIVATE KEY-----" "$APP_STORE_CONNECT_P8_FILE"; then
        printf 'App Store Connect .p8 key file does not look like an App Store Connect private key: %s\n' "$APP_STORE_CONNECT_P8_FILE" >&2
        exit 1
    fi
    local expected_p8_name
    expected_p8_name="AuthKey_${APP_STORE_CONNECT_API_KEY}.p8"
    if [[ "$(basename "$APP_STORE_CONNECT_P8_FILE")" != "$expected_p8_name" && "${CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME:-0}" != "1" ]]; then
        printf 'APP_STORE_CONNECT_P8_FILE basename should be %s for APP_STORE_CONNECT_API_KEY. Set CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1 only after manually verifying the key file belongs to this key ID.\n' "$expected_p8_name" >&2
        exit 1
    fi

    xcode_auth_args=(
        -authenticationKeyPath "$APP_STORE_CONNECT_P8_FILE"
        -authenticationKeyID "$APP_STORE_CONNECT_API_KEY"
        -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER"
    )
    printf 'xcodebuild will use App Store Connect API-key authentication for provisioning updates.\n'
}

run_xcodebuild() {
    if (( ${#xcode_auth_args[@]} > 0 )); then
        xcodebuild "$@" "${xcode_auth_args[@]}"
    else
        xcodebuild "$@"
    fi
}

has_identity() {
    local pattern="$1"
    security find-identity -v -p codesigning 2>/dev/null | rg -q "$pattern"
}

git_commit="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
git_status="$(git -C "$ROOT_DIR" status --short 2>/dev/null || true)"
git_dirty="false"
if [[ -n "$git_status" ]]; then
    git_dirty="true"
fi

kit941_commit="unavailable"
kit941_dirty="unavailable"
kit941_linked_source_dirty="unavailable"
kit941_status=""
kit941_linked_source_status=""
if [[ -d "$KIT941_DIR/.git" ]]; then
    kit941_commit="$(git -C "$KIT941_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
    kit941_dirty_status="$(git -C "$KIT941_DIR" status --short 2>/dev/null || true)"
    kit941_branch_status="$(git -C "$KIT941_DIR" status --short --branch 2>/dev/null || true)"
    kit941_linked_source_status="$(
        {
            git -C "$KIT941_DIR" diff --name-only HEAD -- Package.swift Package.resolved Sources/Kit941
            git -C "$KIT941_DIR" ls-files --others --exclude-standard -- Package.swift Package.resolved Sources/Kit941
        } | sort -u
    )"
    kit941_dirty="false"
    if [[ -n "$kit941_dirty_status" ]]; then
        kit941_dirty="true"
    fi
    kit941_linked_source_dirty="false"
    if [[ -n "$kit941_linked_source_status" ]]; then
        kit941_linked_source_dirty="true"
    fi
    kit941_status="$kit941_branch_status"
fi

if [[ "${CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT:-0}" == "1" && "$git_dirty" == "true" ]]; then
    printf 'Refusing to export from a dirty git tree. Commit or stash changes, or unset CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT.\n' >&2
    printf '%s\n' "$git_status" >&2
    exit 1
fi

if [[ "${CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT:-0}" == "1" && "$kit941_linked_source_dirty" == "true" ]]; then
    printf 'Refusing to export with dirty Kit941 linked package source. Commit or stash changes in %s, or unset CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT.\n' "$KIT941_DIR" >&2
    printf '%s\n' "$kit941_linked_source_status" >&2
    exit 1
fi

if [[ "${CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT:-0}" == "1" && "$kit941_dirty" == "true" ]]; then
    printf 'Continuing with dirty Kit941 files outside linked package source; manifest will record full Kit941 status.\n'
fi

if xcode_version="$(xcodebuild -version 2>/dev/null)" && xcode_sdks="$(xcodebuild -showsdks 2>/dev/null)"; then
    xcode_first_line="$(printf '%s\n' "$xcode_version" | sed -n '1p')"
    xcode_major="$(printf '%s\n' "$xcode_first_line" | sed -E 's/^Xcode ([0-9]+).*/\1/')"
    if ! [[ "$xcode_major" =~ ^[0-9]+$ ]] || (( xcode_major < 26 )); then
        printf '%s is older than Xcode 26 required for 2026 App Store upload.\n' "$xcode_first_line" >&2
        exit 1
    fi
    if ! printf '%s\n' "$xcode_sdks" | rg -q 'macosx(2[6-9]|[3-9][0-9])([.]|$)'; then
        printf '%s does not list a macOS 26 or newer SDK for this release packet.\n' "$xcode_first_line" >&2
        exit 1
    fi
    printf '%s satisfies Xcode 26+ and macOS 26+ SDK requirements.\n' "$xcode_first_line"
else
    printf 'xcodebuild version or SDK list unavailable.\n' >&2
    exit 1
fi

configure_xcode_auth_args

if [[ "${CAPTAINS_LOG_SKIP_DISTRIBUTION_SIGNING_PRECHECK:-0}" != "1" && ${#xcode_auth_args[@]} -eq 0 ]]; then
    app_identity_pattern="\"(Apple Distribution|Mac App Distribution|3rd Party Mac Developer Application):.*\\(${TEAM_ID}\\)\""
    installer_identity_pattern="\"(Mac Installer Distribution|3rd Party Mac Developer Installer):.*\\(${TEAM_ID}\\)\""
    if ! has_identity "$app_identity_pattern"; then
        cat >&2 <<MESSAGE
Mac App Store application signing identity for team ${TEAM_ID} was not found in the local keychain.
Install or create an Apple Distribution/Mac App Distribution certificate for team ${TEAM_ID}, or set APP_STORE_CONNECT_API_KEY, APP_STORE_CONNECT_API_ISSUER, and APP_STORE_CONNECT_P8_FILE so xcodebuild can authenticate for provisioning updates. The Fastlane-compatible ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases are also accepted.
Set CAPTAINS_LOG_SKIP_DISTRIBUTION_SIGNING_PRECHECK=1 to attempt the export anyway.
MESSAGE
        exit 1
    fi
    if ! has_identity "$installer_identity_pattern"; then
        cat >&2 <<MESSAGE
Mac App Store installer signing identity for team ${TEAM_ID} was not found in the local keychain.
Install or create a Mac Installer Distribution certificate for team ${TEAM_ID}, or set APP_STORE_CONNECT_API_KEY, APP_STORE_CONNECT_API_ISSUER, and APP_STORE_CONNECT_P8_FILE so xcodebuild can authenticate for provisioning updates. The Fastlane-compatible ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases are also accepted.
Set CAPTAINS_LOG_SKIP_DISTRIBUTION_SIGNING_PRECHECK=1 to attempt the export anyway.
MESSAGE
        exit 1
    fi
fi

mkdir -p "$OUTPUT_DIR"
staging_dir="$(mktemp -d "$OUTPUT_DIR/.mac-export-staging.XXXXXX")"
staged_archive_path="$staging_dir/$(basename "$ARCHIVE_PATH")"
staged_export_path="$staging_dir/$(basename "$EXPORT_PATH")"
cleanup_staging() {
    rm -rf "$staging_dir"
}
trap cleanup_staging EXIT

export_options="$(mktemp -t captainslog-macos-export-options.XXXXXX.plist)"
trap 'rm -f "$export_options"; cleanup_staging' EXIT

cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST

printf 'Staging macOS archive/export in %s. Existing output will be replaced only after export validation succeeds.\n' "$staging_dir"

run_xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$staged_archive_path" \
    -allowProvisioningUpdates \
    archive

run_xcodebuild \
    -exportArchive \
    -archivePath "$staged_archive_path" \
    -exportPath "$staged_export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates

app_path="$staged_archive_path/Products/Applications/Captain's Log.app"
info_plist="$app_path/Contents/Info.plist"
privacy_manifest="$app_path/Contents/Resources/PrivacyInfo.xcprivacy"
staged_pkg_path="$(find "$staged_export_path" -maxdepth 1 -name "*.pkg" -print -quit)"
staged_export_manifest="$staged_export_path/$(basename "$EXPORT_MANIFEST")"

if [[ ! -d "$app_path" ]]; then
    printf 'Archived macOS app not found: %s\n' "$app_path" >&2
    exit 1
fi

if [[ ! -f "$privacy_manifest" ]]; then
    printf 'Privacy manifest missing from archived macOS app: %s\n' "$privacy_manifest" >&2
    exit 1
fi

if [[ -z "$staged_pkg_path" || ! -f "$staged_pkg_path" ]]; then
    printf 'Exported Mac App Store package not found in: %s\n' "$staged_export_path" >&2
    find "$staged_export_path" -maxdepth 2 -print >&2
    exit 1
fi

archived_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
archived_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
archived_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
archived_category="$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$info_plist")"
created_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
pkg_path="$EXPORT_PATH/$(basename "$staged_pkg_path")"

if [[ "$archived_bundle_id" != "$BUNDLE_ID" ]]; then
    printf 'Unexpected macOS bundle id: %s\n' "$archived_bundle_id" >&2
    exit 1
fi

if [[ "$archived_category" != "public.app-category.developer-tools" ]]; then
    printf 'Unexpected Mac App Store category: %s\n' "$archived_category" >&2
    exit 1
fi

{
    printf "Captain's Log Mac App Store Export\n"
    printf 'Created UTC: %s\n' "$created_utc"
    printf 'Exported app commit: %s\n' "$git_commit"
    printf 'Git dirty at export: %s\n' "$git_dirty"
    printf 'Kit941 path: %s\n' "$KIT941_DIR"
    printf 'Kit941 commit: %s\n' "$kit941_commit"
    printf 'Kit941 dirty at export: %s\n' "$kit941_linked_source_dirty"
    printf 'Kit941 full dirty at export: %s\n' "$kit941_dirty"
    printf 'Archive: %s\n' "$ARCHIVE_PATH"
    printf 'Package: %s\n' "$pkg_path"
    printf 'Bundle: %s\n' "$archived_bundle_id"
    printf 'Version: %s (%s)\n' "$archived_version" "$archived_build"
    printf 'Category: %s\n' "$archived_category"
    printf 'Privacy manifest: present\n'
    if [[ -n "$git_status" ]]; then
        printf 'Git status at export:\n%s\n' "$git_status"
    else
        printf 'Git status at export: clean\n'
    fi
    if [[ -n "$kit941_status" ]]; then
        printf 'Kit941 status at export:\n%s\n' "$kit941_status"
    else
        printf 'Kit941 status at export: unavailable\n'
    fi
    if [[ -n "$kit941_linked_source_status" ]]; then
        printf 'Kit941 linked package source status at export:\n%s\n' "$kit941_linked_source_status"
    else
        printf 'Kit941 linked package source status at export: clean\n'
    fi
} > "$staged_export_manifest"

if [[ ! -s "$staged_export_manifest" ]]; then
    printf 'Mac export manifest was not created in staged output: %s\n' "$staged_export_manifest" >&2
    exit 1
fi

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mv "$staged_archive_path" "$ARCHIVE_PATH"
mv "$staged_export_path" "$EXPORT_PATH"

pkg_path="$(find "$EXPORT_PATH" -maxdepth 1 -name "*.pkg" -print -quit)"

printf 'Archive: %s\n' "$ARCHIVE_PATH"
printf 'Package: %s\n' "$pkg_path"
printf 'Export manifest: %s\n' "$EXPORT_MANIFEST"
printf 'Exported app commit: %s\n' "$git_commit"
printf 'Git dirty at export: %s\n' "$git_dirty"
printf 'Kit941 commit: %s\n' "$kit941_commit"
printf 'Kit941 linked package source dirty at export: %s\n' "$kit941_linked_source_dirty"
printf 'Kit941 full dirty at export: %s\n' "$kit941_dirty"
printf 'Bundle: %s\n' "$archived_bundle_id"
printf 'Version: %s (%s)\n' "$archived_version" "$archived_build"
printf 'Category: %s\n' "$archived_category"
printf 'Privacy manifest: present\n'
