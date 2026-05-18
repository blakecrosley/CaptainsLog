#!/usr/bin/env bash
# Copy these exports into your shell after creating an App Store Connect API key.
# Do not put real values in this file and do not commit a filled-in copy.
#
# Preferred private-key location:
#   mkdir -p "$HOME/.appstoreconnect/private_keys"
#   chmod 700 "$HOME/.appstoreconnect" "$HOME/.appstoreconnect/private_keys"
#   mv "/path/to/downloaded/AuthKey_YOUR_KEY_ID.p8" "$HOME/.appstoreconnect/private_keys/"
#   chmod 600 "$HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"
#
# If multiple AuthKey_*.p8 files are staged locally, choose the matching team
# key ID in App Store Connect > Users and Access > Integrations and keep the
# basename as AuthKey_<KEY_ID>.p8. The release scripts fail early on a mismatch
# unless CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1 is set after manual
# verification.

export APP_STORE_CONNECT_API_KEY="YOUR_KEY_ID"
export APP_STORE_CONNECT_API_ISSUER="YOUR_ISSUER_UUID"
export APP_STORE_CONNECT_P8_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"

# Optional. Fill only if using Scripts/upload_app_store_ipa.sh app-record-altool.
# Xcode 26.5 altool --list-providers does not support API-key authentication.
# The default app-record command uses the App Store Connect REST API and does
# not need this value.
# export APP_STORE_CONNECT_PROVIDER_PUBLIC_ID="YOUR_PROVIDER_PUBLIC_ID"

# Optional. Fill after the app record exists if you want status checks by app.
export APP_STORE_CONNECT_APPLE_ID="YOUR_APPLE_ID"

# Optional. Fill after upload if altool returns a delivery ID.
export APP_STORE_CONNECT_DELIVERY_ID="YOUR_DELIVERY_ID"
