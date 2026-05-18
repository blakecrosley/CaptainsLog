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
ALLOW_MISSING_EXPORT_MANIFEST="${CAPTAINS_LOG_ALLOW_MISSING_EXPORT_MANIFEST:-0}"
ALLOW_DIRTY_EXPORT="${CAPTAINS_LOG_ALLOW_DIRTY_EXPORT:-0}"

usage() {
    cat <<'USAGE'
Usage:
	  Scripts/upload_app_store_ipa.sh local-check [ipa]
	  Scripts/upload_app_store_ipa.sh providers  # reports API-key provider listing limitation
	  Scripts/upload_app_store_ipa.sh app-record         # REST API, no provider public ID required
	  Scripts/upload_app_store_ipa.sh app-record-altool  # legacy altool path, requires provider public ID
	  Scripts/upload_app_store_ipa.sh validate [ipa]
	  Scripts/upload_app_store_ipa.sh upload [ipa]
	  Scripts/upload_app_store_ipa.sh status [ipa]
	  Scripts/upload_app_store_ipa.sh credential-guard-self-test

	Authentication for app-record/validate/upload/status:
  APP_STORE_CONNECT_API_KEY       App Store Connect API key ID.
  APP_STORE_CONNECT_API_ISSUER    App Store Connect issuer UUID.

	Optional:
	  APP_STORE_CONNECT_P8_FILE       Direct path to AuthKey_<key>.p8.
	  APP_STORE_CONNECT_PROVIDER_PUBLIC_ID
	                                  Required only for app-record-altool because
	                                  altool --list-apps requires a provider public ID.
	                                  Xcode 26.5 altool --list-providers does not
	                                  support API-key authentication, so obtain this
	                                  value from App Store Connect, Transporter, or a
	                                  manually authenticated altool session.
	  APP_STORE_CONNECT_DELIVERY_ID   Use for status after upload.
	  APP_STORE_CONNECT_APPLE_ID      App Apple ID for status when delivery ID is unavailable;
	                                  also narrows app-record-altool checks when set.
  APP_STORE_CONNECT_WAIT=1        Wait for upload/status processing.
  ALTOOL_OUTPUT_FORMAT=json       Use altool JSON output.
  CAPTAINS_LOG_ALLOW_MISSING_EXPORT_MANIFEST=1
                                  Allow local-check for a legacy IPA without a sibling ExportManifest.txt.
  CAPTAINS_LOG_ALLOW_DIRTY_EXPORT=1
                                  Allow local-check for an export manifest generated from a dirty git tree.
  CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1
                                  Allow APP_STORE_CONNECT_P8_FILE to use a basename other than
                                  AuthKey_<APP_STORE_CONNECT_API_KEY>.p8 after manual verification.
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

    local bundle_id version build encryption get_task_allow executable_name executable_path
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
    build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
    encryption="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info_plist")"
    get_task_allow="$(codesign -d --entitlements :- "$app_path" 2>/dev/null | plutil -extract get-task-allow raw -o - - 2>/dev/null || true)"
    executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
    executable_path="$app_path/$executable_name"

    [[ "$bundle_id" == "$BUNDLE_ID" ]] || fail "Unexpected bundle id: $bundle_id"
    [[ "$encryption" == "false" ]] || fail "Unexpected ITSAppUsesNonExemptEncryption=$encryption"
    [[ "$get_task_allow" == "false" ]] || fail "Expected get-task-allow=false, got ${get_task_allow:-missing}"
    [[ -f "$executable_path" ]] || fail "App executable missing from IPA app: $executable_path"

    local release_fixture_hits screenshot_fixture_key release_fixture_pattern
    screenshot_fixture_key="$(printf '%s-%s' "sk" "captainslog-screenshot-demo26")"
    release_fixture_pattern="CAPTAINS_LOG_DEBUG_OPENAI_API_KEY|REPS_DEBUG_OPENAI_API_KEY|CAPTAINS_LOG_SCREENSHOT_ROUTE|CAPTAINS_LOG_UI_FIXTURE|CAPTAINS_LOG_UI_TESTING|-ui-testing|${screenshot_fixture_key}"
    if release_fixture_hits="$(strings "$executable_path" | rg "$release_fixture_pattern")"; then
        fail "Release app executable contains debug/test fixture strings:
$(printf '%s\n' "$release_fixture_hits" | sed -n '1,12p')"
    fi

    local exported_commit git_dirty kit941_commit kit941_dirty
    if [[ -f "$export_manifest" ]]; then
        exported_commit="$(awk -F ': ' '/^Exported app commit:/ { print $2; exit }' "$export_manifest")"
        git_dirty="$(awk -F ': ' '/^Git dirty at export:/ { print $2; exit }' "$export_manifest")"
        kit941_commit="$(awk -F ': ' '/^Kit941 commit:/ { print $2; exit }' "$export_manifest")"
        kit941_dirty="$(awk -F ': ' '/^Kit941 dirty at export:/ { print $2; exit }' "$export_manifest")"
        [[ -n "$exported_commit" ]] || fail "Export manifest is missing exported commit: $export_manifest"
        [[ -n "$git_dirty" ]] || fail "Export manifest is missing dirty-tree state: $export_manifest"
        if [[ "$git_dirty" == "true" && "$ALLOW_DIRTY_EXPORT" != "1" ]]; then
            fail "IPA was exported from a dirty git tree. Regenerate from a clean tree or set CAPTAINS_LOG_ALLOW_DIRTY_EXPORT=1."
        fi
        if [[ "$kit941_dirty" == "true" && "$ALLOW_DIRTY_EXPORT" != "1" ]]; then
            fail "IPA was exported with dirty Kit941 source. Regenerate from clean package source or set CAPTAINS_LOG_ALLOW_DIRTY_EXPORT=1."
        fi
    else
        if [[ "$ALLOW_MISSING_EXPORT_MANIFEST" != "1" ]]; then
            fail "Export manifest missing: $export_manifest. Regenerate with Scripts/export_app_store_ipa.sh or set CAPTAINS_LOG_ALLOW_MISSING_EXPORT_MANIFEST=1 for a legacy IPA check."
        fi
        exported_commit=""
        git_dirty=""
        kit941_commit=""
        kit941_dirty=""
    fi

    printf 'IPA local check passed\n'
    printf 'IPA: %s\n' "$ipa_path"
    if [[ -f "$export_manifest" ]]; then
        printf 'Export manifest: present\n'
        [[ -n "$exported_commit" ]] && printf 'Exported app commit: %s\n' "$exported_commit"
        [[ -n "$git_dirty" ]] && printf 'Git dirty at export: %s\n' "$git_dirty"
        [[ -n "$kit941_commit" ]] && printf 'Kit941 commit: %s\n' "$kit941_commit"
        [[ -n "$kit941_dirty" ]] && printf 'Kit941 dirty at export: %s\n' "$kit941_dirty"
    else
        printf 'Export manifest: missing\n'
    fi
    printf 'Bundle: %s\n' "$bundle_id"
    printf 'Version: %s (%s)\n' "$version" "$build"
    printf 'Privacy manifest: present\n'
    printf 'Non-exempt encryption: %s\n' "$encryption"
    printf 'get-task-allow: %s\n' "$get_task_allow"
    printf 'Release fixture strings: absent\n'
}

auth_args=()

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

    [[ -f "$p8_path" ]] || fail "$source_label file does not exist: $p8_path"
    p8_path="$(absolute_path "$p8_path")" || fail "$source_label path is not accessible: $p8_path"

    local p8_git_root
    p8_git_root="$(git_root_for_path "$p8_path")"
    case "$p8_path" in
        "$ROOT_DIR"/*)
            fail "App Store Connect .p8 key file must live outside the repo"
            ;;
    esac
    if [[ -n "$p8_git_root" ]]; then
        fail "App Store Connect .p8 key file must live outside any git working tree: $p8_git_root"
    fi

    [[ -r "$p8_path" ]] || fail "App Store Connect .p8 key file is not readable"

    if ! rg -q -- "-----BEGIN PRIVATE KEY-----" "$p8_path"; then
        fail "App Store Connect .p8 key file does not look like an App Store Connect private key"
    fi

    local expected_p8_name
    expected_p8_name="AuthKey_${APP_STORE_CONNECT_API_KEY}.p8"
    if [[ "$(basename "$p8_path")" != "$expected_p8_name" ]]; then
        if [[ "${CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME:-0}" != "1" ]]; then
            fail "APP_STORE_CONNECT_P8_FILE basename should be $expected_p8_name for APP_STORE_CONNECT_API_KEY. Set CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1 only after manually verifying the key file belongs to this key ID."
        fi
        printf 'warning: App Store Connect .p8 filename is not %s; continuing because CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1\n' "$expected_p8_name" >&2
    fi

    if [[ "$source_label" == "APP_STORE_CONNECT_P8_FILE" ]]; then
        APP_STORE_CONNECT_P8_FILE="$p8_path"
    fi
}

check_api_credentials() {
    [[ "$APP_STORE_CONNECT_API_KEY" =~ ^[A-Za-z0-9]{10}$ ]] || fail "APP_STORE_CONNECT_API_KEY should be a 10-character key ID"
    [[ "$APP_STORE_CONNECT_API_ISSUER" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || fail "APP_STORE_CONNECT_API_ISSUER should be a UUID"

    local default_p8_path
    if [[ -n "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
        check_p8_path "$APP_STORE_CONNECT_P8_FILE" "APP_STORE_CONNECT_P8_FILE"
    elif default_p8_path="$(default_p8_path_for_key "$APP_STORE_CONNECT_API_KEY")"; then
        check_p8_path "$default_p8_path" "altool default private key search path"
    else
        fail "APP_STORE_CONNECT_P8_FILE is not set and AuthKey_<key>.p8 was not found in altool's default private key search paths"
    fi
}

assert_app_record_output_contains_bundle() {
    local output="$1"

    if printf '%s\n' "$output" | rg -q --fixed-strings "$BUNDLE_ID"; then
        return 0
    fi

    fail "App Store Connect app record not found for bundle id $BUNDLE_ID. Create the app record or verify API-key visibility."
}

credential_guard_self_test() {
    local temp_dir test_key test_issuer good_p8 bad_p8 mismatched_p8
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' RETURN

    test_key="ABCDEFGHIJ"
    test_issuer="00000000-0000-0000-0000-000000000000"
    good_p8="$temp_dir/AuthKey_${test_key}.p8"
    bad_p8="$temp_dir/AuthKey_BADHEADER.p8"
    mismatched_p8="$temp_dir/AuthKey_ZZZZZZZZZZ.p8"

    printf '%s\n%s\n%s\n' "-----BEGIN PRIVATE KEY-----" "fake-self-test-key" "-----END PRIVATE KEY-----" >"$good_p8"
    printf '%s\n' "not a private key" >"$bad_p8"
    printf '%s\n%s\n%s\n' "-----BEGIN PRIVATE KEY-----" "fake-self-test-key" "-----END PRIVATE KEY-----" >"$mismatched_p8"

    good_direct_path() {
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        APP_STORE_CONNECT_P8_FILE="$good_p8"
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    good_default_path() {
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        unset APP_STORE_CONNECT_P8_FILE
        API_PRIVATE_KEYS_DIR="$temp_dir"
        check_api_credentials
    }

    bad_key_shape() {
        APP_STORE_CONNECT_API_KEY="SHORT"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        APP_STORE_CONNECT_P8_FILE="$good_p8"
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    bad_issuer_shape() {
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="not-a-uuid"
        APP_STORE_CONNECT_P8_FILE="$good_p8"
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    missing_p8() {
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        APP_STORE_CONNECT_P8_FILE="$temp_dir/missing.p8"
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    repo_local_p8() {
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        APP_STORE_CONNECT_P8_FILE="$ROOT_DIR/Scripts/upload_app_store_ipa.sh"
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    bad_p8_header() {
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        APP_STORE_CONNECT_P8_FILE="$bad_p8"
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    mismatched_p8_filename() {
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        APP_STORE_CONNECT_P8_FILE="$mismatched_p8"
        CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=0
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    mismatched_p8_filename_allowed() {
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        APP_STORE_CONNECT_P8_FILE="$mismatched_p8"
        CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    no_p8_available() {
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        unset APP_STORE_CONNECT_P8_FILE
        API_PRIVATE_KEYS_DIR="$temp_dir/empty"
        check_api_credentials
    }

    symlink_to_repo_local_p8() {
        local link_path="$temp_dir/AuthKey_${test_key}.p8"
        ln -sf "$ROOT_DIR/Scripts/upload_app_store_ipa.sh" "$link_path"
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        APP_STORE_CONNECT_P8_FILE="$link_path"
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    p8_inside_other_git_repo() {
        local foreign_repo foreign_p8
        foreign_repo="$temp_dir/foreign-repo"
        foreign_p8="$foreign_repo/AuthKey_${test_key}.p8"
        mkdir -p "$foreign_repo"
        git -C "$foreign_repo" init -q
        printf '%s\n%s\n%s\n' "-----BEGIN PRIVATE KEY-----" "fake-self-test-key" "-----END PRIVATE KEY-----" >"$foreign_p8"
        APP_STORE_CONNECT_API_KEY="$test_key"
        APP_STORE_CONNECT_API_ISSUER="$test_issuer"
        APP_STORE_CONNECT_P8_FILE="$foreign_p8"
        unset API_PRIVATE_KEYS_DIR
        check_api_credentials
    }

    good_app_record_output() {
        assert_app_record_output_contains_bundle "{\"data\":[{\"bundleId\":\"$BUNDLE_ID\"}]}"
    }

    bad_app_record_output() {
        assert_app_record_output_contains_bundle '{"data":[]}'
    }

    expect_pass() {
        local label="$1"
        shift
        if ( "$@" ) >/dev/null 2>&1; then
            printf '[ok] credential guard accepts %s\n' "$label"
        else
            fail "credential guard should accept $label"
        fi
    }

    expect_fail() {
        local label="$1"
        shift
        if ( "$@" ) >/dev/null 2>&1; then
            fail "credential guard should reject $label"
        else
            printf '[ok] credential guard rejects %s\n' "$label"
        fi
    }

    expect_pass "direct .p8 path outside repo" good_direct_path
    expect_pass "altool default .p8 path outside repo" good_default_path
    expect_fail "malformed API key ID" bad_key_shape
    expect_fail "malformed issuer UUID" bad_issuer_shape
    expect_fail "missing .p8 path" missing_p8
    expect_fail "repo-local .p8 path" repo_local_p8
    expect_fail "symlink to repo-local .p8 path" symlink_to_repo_local_p8
    expect_fail ".p8 path inside another git repo" p8_inside_other_git_repo
    expect_fail "non-private-key .p8 file" bad_p8_header
    expect_fail "mismatched .p8 filename" mismatched_p8_filename
    expect_pass "mismatched .p8 filename with explicit override" mismatched_p8_filename_allowed
    expect_fail "missing default .p8 file" no_p8_available
    expect_pass "app-record output containing bundle id" good_app_record_output
    expect_fail "app-record output missing bundle id" bad_app_record_output

    printf 'Credential guard self-test passed\n'
}

build_auth_args() {
    local include_provider="${1:-1}"

    if [[ -n "${APP_STORE_CONNECT_API_KEY:-}" && -n "${APP_STORE_CONNECT_API_ISSUER:-}" ]]; then
        check_api_credentials
        auth_args=(
            --api-key "$APP_STORE_CONNECT_API_KEY"
            --api-issuer "$APP_STORE_CONNECT_API_ISSUER"
        )
        if [[ -n "${APP_STORE_CONNECT_P8_FILE:-}" ]]; then
            auth_args+=(--p8-file-path "$APP_STORE_CONNECT_P8_FILE")
        fi
    else
        fail "Set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER before using $COMMAND"
    fi

    if [[ "$include_provider" == "1" && -n "${APP_STORE_CONNECT_PROVIDER_PUBLIC_ID:-}" ]]; then
        auth_args+=(--provider-public-id "$APP_STORE_CONNECT_PROVIDER_PUBLIC_ID")
    fi
}

require_provider_public_id() {
    [[ -n "${APP_STORE_CONNECT_PROVIDER_PUBLIC_ID:-}" ]] || fail "Set APP_STORE_CONNECT_PROVIDER_PUBLIC_ID before using app-record-altool. Xcode 26.5 altool --list-providers does not support API-key authentication; obtain the provider public ID from App Store Connect, Transporter, or a manually authenticated altool session."
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

run_providers() {
    fail "Xcode 26.5 altool --list-providers does not support API-key authentication. Use app-record for the REST API check, or obtain APP_STORE_CONNECT_PROVIDER_PUBLIC_ID from App Store Connect, Transporter, or a manually authenticated altool session before app-record-altool."
}

run_app_record() {
    [[ -x "$ROOT_DIR/Scripts/check_app_store_connect_record.py" ]] || fail "Scripts/check_app_store_connect_record.py is missing or not executable"
    if [[ "$ALTOOL_OUTPUT_FORMAT" == "json" ]]; then
        "$ROOT_DIR/Scripts/check_app_store_connect_record.py" --bundle-id "$BUNDLE_ID" --json
    else
        "$ROOT_DIR/Scripts/check_app_store_connect_record.py" --bundle-id "$BUNDLE_ID"
    fi
}

run_app_record_altool() {
    build_auth_args 0
    require_provider_public_id

    local args=(
        --list-apps
        --provider-public-id "$APP_STORE_CONNECT_PROVIDER_PUBLIC_ID"
        --filter-bundle-id "$BUNDLE_ID"
        "${auth_args[@]}"
        --output-format "$ALTOOL_OUTPUT_FORMAT"
    )

    if [[ -n "${APP_STORE_CONNECT_APPLE_ID:-}" ]]; then
        args+=(--filter-apple-id "$APP_STORE_CONNECT_APPLE_ID")
    fi

    local output
    if ! output="$(xcrun altool "${args[@]}" 2>&1)"; then
        printf '%s\n' "$output" >&2
        return 1
    fi

    printf '%s\n' "$output"
    assert_app_record_output_contains_bundle "$output"
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
    providers)
        run_providers
        ;;
	    app-record)
	        run_app_record
	        ;;
	    app-record-altool)
	        run_app_record_altool
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
    credential-guard-self-test)
        credential_guard_self_test
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        fail "Unknown command: $COMMAND"
        ;;
esac
