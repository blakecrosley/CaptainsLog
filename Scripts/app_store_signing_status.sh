#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="M4WTLM6RAQ"
BUNDLE_ID="com.blakecrosley.captainslog"

failures=0

pass() {
    printf '[ok] %s\n' "$1"
}

warn() {
    printf '[warn] %s\n' "$1"
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

printf "Captain's Log App Store signing status\n"
printf 'Repo: %s\n' "$ROOT_DIR"
printf 'Team ID: %s\n' "$TEAM_ID"
printf 'Bundle ID: %s\n\n' "$BUNDLE_ID"

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
    elif printf '%s\n' "$xcode_sdks" | rg -q 'iphoneos(2[6-9]|[3-9][0-9])([.]|$)'; then
        pass "$xcode_first_line satisfies Xcode 26+ and iOS 26+ SDK requirements"
    else
        fail "$xcode_first_line does not list an iOS 26 or newer SDK required for 2026 App Store upload"
    fi
else
    fail "xcodebuild version or SDK list unavailable"
fi

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
    fail "Apple Distribution/iOS Distribution signing identity for team ${TEAM_ID} is missing"
fi

if printf '%s\n' "$identity_output" | rg -q '"Apple Development:'; then
    pass "Apple Development signing identity is available"
else
    warn "Apple Development signing identity is missing"
fi

if printf '%s\n' "$identity_output" | rg -q '"Developer ID Application:'; then
    warn "Developer ID Application identity is present, but it is for macOS distribution and cannot export this iOS App Store IPA"
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
Make App Store distribution signing available to Xcode:

1. Open Xcode > Settings > Accounts.
2. Sign into an Apple ID that belongs to team ${TEAM_ID}.
3. Select the team, open Manage Certificates, then use + > Apple Distribution.
4. If profiles still look stale afterward, use Download Manual Profiles.

After the distribution identity appears in this command, regenerate the current IPA:

  CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export

Then rerun:

  Scripts/app_store_readiness_status.sh
NEXT
    exit 1
fi

cat <<NEXT
Signing looks locally ready. Regenerate the current IPA:

  CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
NEXT
