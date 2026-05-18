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
if xcode_version="$(xcodebuild -version 2>/dev/null)"; then
    printf '%s\n' "$xcode_version" | sed -n '1,2p'
else
    fail "xcodebuild version unavailable"
fi

printf '\nCode signing identities\n'
identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "$identity_output" ]]; then
    printf '%s\n' "$identity_output" | sed -n '1,20p'
else
    fail "no code signing identities returned by security"
fi

if printf '%s\n' "$identity_output" | rg -q '"(Apple Distribution|iOS Distribution):'; then
    pass "Apple Distribution/iOS Distribution signing identity is available"
else
    fail "Apple Distribution/iOS Distribution signing identity is missing"
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
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
if [[ -d "$profile_dir" ]]; then
    profile_count="$(find "$profile_dir" -maxdepth 1 -type f -name '*.mobileprovision' | wc -l | tr -d ' ')"
    pass "provisioning profile directory exists: $profile_count profile(s)"
else
    warn "provisioning profile directory missing: $profile_dir"
fi

printf '\nNext step\n'
if (( failures > 0 )); then
    cat <<NEXT
Open Xcode Settings > Accounts, sign into the App Store Connect team, then create or download an Apple Distribution certificate for team ${TEAM_ID}.

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
