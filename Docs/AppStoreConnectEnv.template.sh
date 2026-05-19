#!/usr/bin/env bash
# Copy this file to AppStoreConnectEnv.local.sh after creating an App Store
# Connect API key. The release scripts load AppStoreConnectEnv.local.sh from the
# repo root or Docs/ automatically. Do not put real values in this tracked file
# and do not commit a filled-in copy.
#
# Preferred private-key location:
#   mkdir -p "$HOME/.appstoreconnect/private_keys"
#   chmod 700 "$HOME/.appstoreconnect" "$HOME/.appstoreconnect/private_keys"
#   mv "/path/to/downloaded/AuthKey_YOUR_KEY_ID.p8" "$HOME/.appstoreconnect/private_keys/"
#   chmod 600 "$HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"
#
# If multiple AuthKey_*.p8 files are staged locally, choose the matching team
# key ID in App Store Connect > Users and Access > Integrations and keep the
# basename as AuthKey_<KEY_ID>.p8. APP_STORE_CONNECT_P8_FILE may be omitted when
# the matching file already exists in the preferred private-key location. Do not
# point APP_STORE_CONNECT_P8_FILE at a key stored inside another app repo or
# Fastlane folder; the release scripts reject private keys inside any git working
# tree. The release scripts also fail early on a filename mismatch unless
# CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1 is set after manual verification.
#
# If reusing Fastlane-style variables from Return or Get Bananas, the release
# scripts also accept ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH directly when
# APP_STORE_CONNECT_* is unset. ASC_KEY_PATH may be omitted when the matching
# AuthKey_<KEY_ID>.p8 file exists in the preferred private-key location. If you
# do set ASC_KEY_PATH, make sure it points outside every git working tree.

export APP_STORE_CONNECT_API_KEY="YOUR_KEY_ID"
export APP_STORE_CONNECT_API_ISSUER="YOUR_ISSUER_UUID"
# Optional when the matching file is at:
#   $HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8
# export APP_STORE_CONNECT_P8_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"

# Fastlane-compatible aliases. Leave commented if using the canonical names.
# export ASC_KEY_ID="YOUR_KEY_ID"
# export ASC_ISSUER_ID="YOUR_ISSUER_UUID"
# export ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"

# Optional. Fill only if using Scripts/upload_app_store_ipa.sh app-record-altool.
# Xcode 26.5 altool --list-providers does not support API-key authentication.
# The default app-record command uses the App Store Connect REST API and does
# not need this value.
# export APP_STORE_CONNECT_PROVIDER_PUBLIC_ID="YOUR_PROVIDER_PUBLIC_ID"

# Optional. Fill after the app record exists if you want status checks by app.
export APP_STORE_CONNECT_APPLE_ID="YOUR_APPLE_ID"

# Optional. Fill after upload if altool returns a delivery ID.
export APP_STORE_CONNECT_DELIVERY_ID="YOUR_DELIVERY_ID"
