#!/usr/bin/env bash

# Reuse the Fastlane-style App Store Connect names used by nearby apps, while
# keeping APP_STORE_CONNECT_* as the canonical names inside Captain's Log scripts.
app_store_connect_load_local_env() {
    local env_file

    if [[ -n "${CAPTAINS_LOG_APP_STORE_CONNECT_ENV_FILE:-}" ]]; then
        if [[ ! -f "$CAPTAINS_LOG_APP_STORE_CONNECT_ENV_FILE" ]]; then
            printf 'CAPTAINS_LOG_APP_STORE_CONNECT_ENV_FILE does not exist: %s\n' "$CAPTAINS_LOG_APP_STORE_CONNECT_ENV_FILE" >&2
            return 1
        fi
        # shellcheck source=/dev/null
        source "$CAPTAINS_LOG_APP_STORE_CONNECT_ENV_FILE"
        return
    fi

    if [[ -z "${ROOT_DIR:-}" ]]; then
        return
    fi

    for env_file in "$ROOT_DIR/AppStoreConnectEnv.local.sh" "$ROOT_DIR/Docs/AppStoreConnectEnv.local.sh"; do
        [[ -f "$env_file" ]] || continue
        # shellcheck source=/dev/null
        source "$env_file"
    done
}

app_store_connect_apply_fastlane_aliases() {
    if [[ -z "${APP_STORE_CONNECT_API_KEY:-}" && -n "${ASC_KEY_ID:-}" ]]; then
        APP_STORE_CONNECT_API_KEY="$ASC_KEY_ID"
        export APP_STORE_CONNECT_API_KEY
    fi

    if [[ -z "${APP_STORE_CONNECT_API_ISSUER:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
        APP_STORE_CONNECT_API_ISSUER="$ASC_ISSUER_ID"
        export APP_STORE_CONNECT_API_ISSUER
    fi

    if [[ -z "${APP_STORE_CONNECT_P8_FILE:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
        APP_STORE_CONNECT_P8_FILE="$ASC_KEY_PATH"
        export APP_STORE_CONNECT_P8_FILE
    fi
}

app_store_connect_default_p8_path_for_key() {
    local api_key="$1"
    local expected_name="AuthKey_${api_key}.p8"
    local dirs=(
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
            realpath "$candidate"
            return 0
        fi
    done

    return 1
}

app_store_connect_apply_default_p8_file() {
    local default_p8_file

    if [[ -n "${APP_STORE_CONNECT_P8_FILE:-}" || -z "${APP_STORE_CONNECT_API_KEY:-}" ]]; then
        return
    fi

    if default_p8_file="$(app_store_connect_default_p8_path_for_key "$APP_STORE_CONNECT_API_KEY")"; then
        APP_STORE_CONNECT_P8_FILE="$default_p8_file"
        export APP_STORE_CONNECT_P8_FILE
    fi
}

app_store_connect_apply_env_defaults() {
    app_store_connect_load_local_env
    app_store_connect_apply_fastlane_aliases
    app_store_connect_apply_default_p8_file
}

app_store_connect_auth_env_hint() {
    cat <<'MESSAGE'
Set APP_STORE_CONNECT_API_KEY and APP_STORE_CONNECT_API_ISSUER to let xcodebuild authenticate with App Store Connect.
APP_STORE_CONNECT_P8_FILE is required unless AuthKey_<key>.p8 exists in a supported private key directory such as ~/.appstoreconnect/private_keys.
Fastlane-compatible aliases are also accepted when the canonical variables are unset: ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH.
Use Docs/AppStoreConnectEnv.template.sh as the placeholder-only template. Copy real values into the gitignored AppStoreConnectEnv.local.sh or set CAPTAINS_LOG_APP_STORE_CONNECT_ENV_FILE to a private shell file.
MESSAGE
}
