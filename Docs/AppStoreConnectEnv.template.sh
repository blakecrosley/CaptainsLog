#!/usr/bin/env bash
# Copy these exports into your shell after creating an App Store Connect API key.
# Do not put real values in this file and do not commit a filled-in copy.

export APP_STORE_CONNECT_API_KEY="YOUR_KEY_ID"
export APP_STORE_CONNECT_API_ISSUER="YOUR_ISSUER_UUID"
export APP_STORE_CONNECT_P8_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"

# Fill this after running:
#   Scripts/upload_app_store_ipa.sh providers
export APP_STORE_CONNECT_PROVIDER_PUBLIC_ID="YOUR_PROVIDER_PUBLIC_ID"

# Optional. Fill after the app record exists if you want status checks by app.
export APP_STORE_CONNECT_APPLE_ID="YOUR_APPLE_ID"

# Optional. Fill after upload if altool returns a delivery ID.
export APP_STORE_CONNECT_DELIVERY_ID="YOUR_DELIVERY_ID"
