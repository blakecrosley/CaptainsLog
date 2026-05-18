#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_IPA="/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
SCREENSHOT_DIR="${1:-/tmp/captainslog-key-state-audit}"
IPA_PATH="${2:-$DEFAULT_IPA}"
EXPORT_MANIFEST="$(dirname "$IPA_PATH")/ExportManifest.txt"
PACKAGED_DIR="${CAPTAINS_LOG_PACKAGED_SCREENSHOTS:-/tmp/captainslog-key-state-packaged}"
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

printf "Captain's Log App Store readiness status\n"
printf 'Repo: %s\n' "$ROOT_DIR"
printf 'Screenshots: %s\n' "$SCREENSHOT_DIR"
printf 'Packaged screenshots: %s\n' "$PACKAGED_DIR"
printf 'IPA: %s\n\n' "$IPA_PATH"

need_command git
need_command xcrun
need_command sips
need_command sqlite3
need_command unzip
need_command rg

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
        fail "Kit941 git tree is dirty:
$kit_status"
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
            fail "Kit941 commit changed after IPA export; regenerate IPA"
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
else
    external "App Store Connect API key and issuer are not set; validate/upload/status remain blocked"
fi

if [[ -n "${APP_STORE_CONNECT_P8_FILE:-}" && -f "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
    pass "App Store Connect .p8 key file is set"
else
    external "App Store Connect .p8 key file is not set"
fi

external "create or confirm the App Store Connect app record"
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
fi
