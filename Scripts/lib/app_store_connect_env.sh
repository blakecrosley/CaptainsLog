#!/usr/bin/env bash

# Reuse the Fastlane-style App Store Connect names used by nearby apps, while
# keeping APP_STORE_CONNECT_* as the canonical names inside Captain's Log scripts.
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

app_store_connect_auth_env_hint() {
    cat <<'MESSAGE'
Set APP_STORE_CONNECT_API_KEY, APP_STORE_CONNECT_API_ISSUER, and APP_STORE_CONNECT_P8_FILE together to let xcodebuild authenticate with App Store Connect.
Fastlane-compatible aliases are also accepted when the canonical variables are unset: ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH.
Use Docs/AppStoreConnectEnv.template.sh as the placeholder-only template.
MESSAGE
}
