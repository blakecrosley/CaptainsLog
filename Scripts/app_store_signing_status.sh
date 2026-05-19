#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="M4WTLM6RAQ"
IOS_BUNDLE_ID="com.blakecrosley.captainslog"
MACOS_BUNDLE_ID="com.blakecrosley.captainslog.mac"

failures=0
xcode_auth_env_ready=0
cloud_signing_attempt_only=0

# shellcheck source=Scripts/lib/app_store_connect_env.sh
source "$ROOT_DIR/Scripts/lib/app_store_connect_env.sh"

pass() {
    printf '[ok] %s\n' "$1"
}

warn() {
    printf '[warn] %s\n' "$1"
}

info() {
    printf '[info] %s\n' "$1"
}

fail() {
    printf '[fail] %s\n' "$1" >&2
    failures=$((failures + 1))
}

need_command() {
    if command -v "$1" >/dev/null 2>&1; then
        pass "command available: $1"
    else
        fail "command missing: $1"
    fi
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

check_xcode_auth_env() {
    local has_any_auth_value=0
    local p8_candidate_count
    app_store_connect_apply_fastlane_aliases

    if [[ -n "${APP_STORE_CONNECT_API_KEY:-}" || -n "${APP_STORE_CONNECT_API_ISSUER:-}" || -n "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
        has_any_auth_value=1
    fi

    printf '\nApp Store Connect xcodebuild authentication\n'
    if (( has_any_auth_value == 0 )); then
        warn "APP_STORE_CONNECT_API_KEY, APP_STORE_CONNECT_API_ISSUER, and APP_STORE_CONNECT_P8_FILE are not set; Fastlane ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases are also unset"
        p8_candidate_count="$(default_p8_candidate_count)"
        if (( p8_candidate_count > 0 )); then
            warn "$p8_candidate_count candidate App Store Connect .p8 private-key file(s) are staged outside the repo, but no selected API key ID or issuer UUID is set"
            while IFS= read -r candidate_name; do
                [[ -n "$candidate_name" ]] || continue
                info "staged App Store Connect key candidate: $candidate_name"
            done < <(default_p8_candidate_names)
            if (( p8_candidate_count > 1 )); then
                warn "multiple candidate .p8 files found; set APP_STORE_CONNECT_P8_FILE explicitly to the key that matches APP_STORE_CONNECT_API_KEY"
            fi
        fi
        warn "xcodebuild provisioning updates will require a signed-in Xcode account or a local distribution identity"
        return
    fi

    if [[ -z "${APP_STORE_CONNECT_API_KEY:-}" || -z "${APP_STORE_CONNECT_API_ISSUER:-}" || -z "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
        fail "set APP_STORE_CONNECT_API_KEY, APP_STORE_CONNECT_API_ISSUER, and APP_STORE_CONNECT_P8_FILE together for xcodebuild API-key authentication, or use ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases"
        return
    fi

    if [[ "$APP_STORE_CONNECT_API_KEY" =~ ^[A-Za-z0-9]{10}$ ]]; then
        pass "App Store Connect API key ID shape looks valid"
    else
        fail "APP_STORE_CONNECT_API_KEY should be a 10-character key ID"
        return
    fi

    if [[ "$APP_STORE_CONNECT_API_ISSUER" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
        pass "App Store Connect issuer shape looks valid"
    else
        fail "APP_STORE_CONNECT_API_ISSUER should be a UUID"
        return
    fi

    if [[ ! -f "$APP_STORE_CONNECT_P8_FILE" ]]; then
        fail "APP_STORE_CONNECT_P8_FILE does not exist: $APP_STORE_CONNECT_P8_FILE"
        return
    fi

    APP_STORE_CONNECT_P8_FILE="$(absolute_path "$APP_STORE_CONNECT_P8_FILE")"
    local p8_git_root
    p8_git_root="$(git_root_for_path "$APP_STORE_CONNECT_P8_FILE")"
    case "$APP_STORE_CONNECT_P8_FILE" in
        "$ROOT_DIR"/*)
            fail "App Store Connect .p8 key file must live outside this repo: $APP_STORE_CONNECT_P8_FILE"
            return
            ;;
        *)
            pass "App Store Connect .p8 key file is outside this repo"
            ;;
    esac

    if [[ -n "$p8_git_root" ]]; then
        fail "App Store Connect .p8 key file must live outside any git working tree: $p8_git_root"
        return
    else
        pass "App Store Connect .p8 key file is outside git working trees"
    fi

    if [[ -r "$APP_STORE_CONNECT_P8_FILE" ]]; then
        pass "App Store Connect .p8 key file is readable"
    else
        fail "App Store Connect .p8 key file is not readable: $APP_STORE_CONNECT_P8_FILE"
        return
    fi

    if rg -q -- "-----BEGIN PRIVATE KEY-----" "$APP_STORE_CONNECT_P8_FILE"; then
        pass "App Store Connect .p8 key file has a private-key header"
    else
        fail "App Store Connect .p8 key file does not look like an App Store Connect private key: $APP_STORE_CONNECT_P8_FILE"
        return
    fi

    local expected_p8_name
    expected_p8_name="AuthKey_${APP_STORE_CONNECT_API_KEY}.p8"
    if [[ "$(basename "$APP_STORE_CONNECT_P8_FILE")" == "$expected_p8_name" ]]; then
        pass "App Store Connect .p8 filename matches APP_STORE_CONNECT_API_KEY"
    elif [[ "${CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME:-0}" == "1" ]]; then
        warn "App Store Connect .p8 filename is not $expected_p8_name; continuing because CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1"
    else
        fail "APP_STORE_CONNECT_P8_FILE basename should be $expected_p8_name for APP_STORE_CONNECT_API_KEY. Set CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1 only after manually verifying the key file belongs to this key ID."
        return
    fi

    xcode_auth_env_ready=1
    pass "xcodebuild App Store Connect API-key auth inputs are present for provisioning updates"
}

printf "Captain's Log App Store signing status\n"
printf 'Repo: %s\n' "$ROOT_DIR"
printf 'Team ID: %s\n' "$TEAM_ID"
printf 'iOS bundle ID: %s\n' "$IOS_BUNDLE_ID"
printf 'macOS bundle ID: %s\n\n' "$MACOS_BUNDLE_ID"

need_command git
need_command security
need_command xcodebuild
need_command rg

printf '\nXcode\n'
if xcode_version="$(xcodebuild -version 2>/dev/null)" && xcode_sdks="$(xcodebuild -showsdks 2>/dev/null)"; then
    printf '%s\n' "$xcode_version" | sed -n '1,2p'
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

check_xcode_auth_env

printf '\nCode signing identities\n'
identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "$identity_output" ]]; then
    printf '%s\n' "$identity_output" | sed -n '1,20p'
else
    fail "no code signing identities returned by security"
fi

if printf '%s\n' "$identity_output" | rg -q "\"(Apple Distribution|iOS Distribution):.*\\(${TEAM_ID}\\)\""; then
    pass "Apple Distribution/iOS Distribution signing identity is available for team ${TEAM_ID}"
else
    if printf '%s\n' "$identity_output" | rg -q '"(Apple Distribution|iOS Distribution):'; then
        warn "Apple Distribution/iOS Distribution signing identity exists, but not for team ${TEAM_ID}"
    fi
    if (( xcode_auth_env_ready == 1 )); then
        warn "Apple Distribution/iOS Distribution signing identity for team ${TEAM_ID} is missing"
        warn "iOS export can attempt cloud-managed signing with the App Store Connect API-key inputs, but exportArchive must still prove cloud certificate access"
        cloud_signing_attempt_only=1
    else
        fail "Apple Distribution/iOS Distribution signing identity for team ${TEAM_ID} is missing"
    fi
fi

if printf '%s\n' "$identity_output" | rg -q "\"(Apple Distribution|Mac App Distribution|3rd Party Mac Developer Application):.*\\(${TEAM_ID}\\)\""; then
    pass "Mac App Store application signing identity is available for team ${TEAM_ID}"
else
    if printf '%s\n' "$identity_output" | rg -q '"(Mac App Distribution|3rd Party Mac Developer Application):'; then
        warn "Mac App Store application signing identity exists, but not for team ${TEAM_ID}"
    fi
    if (( xcode_auth_env_ready == 1 )); then
        warn "Mac App Store application signing identity for team ${TEAM_ID} is missing"
        warn "Mac export can attempt cloud-managed signing with the App Store Connect API-key inputs, but exportArchive must still prove cloud certificate access"
        cloud_signing_attempt_only=1
    else
        fail "Mac App Store application signing identity for team ${TEAM_ID} is missing"
    fi
fi

if printf '%s\n' "$identity_output" | rg -q "\"(Mac Installer Distribution|3rd Party Mac Developer Installer):.*\\(${TEAM_ID}\\)\""; then
    pass "Mac App Store installer signing identity is available for team ${TEAM_ID}"
else
    if printf '%s\n' "$identity_output" | rg -q '"(Mac Installer Distribution|3rd Party Mac Developer Installer):'; then
        warn "Mac App Store installer signing identity exists, but not for team ${TEAM_ID}"
    fi
    if (( xcode_auth_env_ready == 1 )); then
        warn "Mac App Store installer signing identity for team ${TEAM_ID} is missing"
        warn "Mac export can attempt cloud-managed signing with the App Store Connect API-key inputs, but exportArchive must still prove cloud certificate access"
        cloud_signing_attempt_only=1
    else
        fail "Mac App Store installer signing identity for team ${TEAM_ID} is missing"
    fi
fi

if printf '%s\n' "$identity_output" | rg -q '"Apple Development:'; then
    pass "Apple Development signing identity is available"
else
    warn "Apple Development signing identity is missing"
fi

if printf '%s\n' "$identity_output" | rg -q '"Developer ID Application:'; then
    warn "Developer ID Application identity is present, but it cannot export this iOS App Store IPA or a Mac App Store package"
fi

printf '\nProvisioning profiles\n'
profile_dirs=(
    "$HOME/Library/MobileDevice/Provisioning Profiles"
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
)
profile_total=0
for profile_dir in "${profile_dirs[@]}"; do
    if [[ -d "$profile_dir" ]]; then
        profile_count="$(find "$profile_dir" -maxdepth 1 -type f \( -name '*.mobileprovision' -o -name '*.provisionprofile' \) | wc -l | tr -d ' ')"
        profile_total=$((profile_total + profile_count))
        if [[ "$profile_count" == "0" ]]; then
            warn "profile directory exists but contains 0 profile(s): $profile_dir"
        else
            pass "profile directory exists: $profile_count profile(s) in $profile_dir"
        fi
    else
        warn "profile directory missing: $profile_dir"
    fi
done

if (( profile_total == 0 )); then
    warn "no local provisioning profiles found; Xcode may download or create profiles after account signing is configured"
else
    pass "local provisioning profiles available: $profile_total total"
fi

printf '\nNext step\n'
if (( failures > 0 )); then
    cat <<NEXT
Make App Store export signing available with one of these paths:

A. Configure API-key authentication for xcodebuild provisioning updates:
   1. Copy Docs/AppStoreConnectEnv.template.sh to a private shell session.
   2. Set APP_STORE_CONNECT_API_KEY, APP_STORE_CONNECT_API_ISSUER, and APP_STORE_CONNECT_P8_FILE, or reuse the Fastlane-style ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH aliases.
   3. Keep the .p8 outside this repo and outside any git working tree.

B. Or use Xcode account signing:
   1. Open Xcode > Settings > Accounts.
   2. Sign into an Apple ID that belongs to team ${TEAM_ID}.
   3. Select the team, open Manage Certificates, then use + > Apple Distribution.
   4. For native Mac App Store export, also create or install a Mac Installer Distribution certificate if Xcode does not create it automatically.
   5. If profiles still look stale afterward, use Download Manual Profiles.

After one signing path is ready, regenerate the current IPA:

  CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export

If intentionally adding the native Mac app to this release, also regenerate the Mac App Store package:

  CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export

Then rerun:

  Scripts/app_store_readiness_status.sh
NEXT
    exit 1
fi

if (( cloud_signing_attempt_only == 1 )); then
    cat <<NEXT
API-key provisioning inputs are present, but one or more local App Store distribution identities are missing.
This can attempt an export only if the App Store Connect account has cloud-managed distribution certificate access.
If exportArchive reports a cloud signing permission error, grant that access or install the matching local distribution identity with its private key.

Regenerate the current IPA to verify the real signing path:

  CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export

If intentionally adding the native Mac app to this release, also regenerate the Mac App Store package:

  CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export
NEXT
    exit 0
fi

cat <<NEXT
Signing looks locally ready. Regenerate the current IPA:

  CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export

If intentionally adding the native Mac app to this release, also regenerate the Mac App Store package:

  CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export
NEXT
