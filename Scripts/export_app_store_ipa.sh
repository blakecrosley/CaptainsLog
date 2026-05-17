#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/CaptainsLog.xcodeproj"
SCHEME="CaptainsLog-iOS"
TEAM_ID="M4WTLM6RAQ"
BUNDLE_ID="com.blakecrosley.captainslog"
OUTPUT_DIR="${1:-$ROOT_DIR/Artifacts/AppStoreExport}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$OUTPUT_DIR/CaptainsLog.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$OUTPUT_DIR/Export}"

mkdir -p "$OUTPUT_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

export_options="$(mktemp -t captainslog-export-options.XXXXXX.plist)"
trap 'rm -f "$export_options"' EXIT

cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    archive

xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates

app_path="$ARCHIVE_PATH/Products/Applications/Captain's Log.app"
info_plist="$app_path/Info.plist"
privacy_manifest="$app_path/PrivacyInfo.xcprivacy"
ipa_path="$(find "$EXPORT_PATH" -maxdepth 1 -name "*.ipa" -print -quit)"

if [[ ! -d "$app_path" ]]; then
    printf 'Archived app not found: %s\n' "$app_path" >&2
    exit 1
fi

if [[ ! -f "$privacy_manifest" ]]; then
    printf 'Privacy manifest missing from archived app: %s\n' "$privacy_manifest" >&2
    exit 1
fi

if [[ -z "$ipa_path" || ! -f "$ipa_path" ]]; then
    printf 'Exported IPA not found in: %s\n' "$EXPORT_PATH" >&2
    exit 1
fi

archived_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
archived_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
archived_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
uses_non_exempt_encryption="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$info_plist")"

if [[ "$archived_bundle_id" != "$BUNDLE_ID" ]]; then
    printf 'Unexpected bundle id: %s\n' "$archived_bundle_id" >&2
    exit 1
fi

if [[ "$uses_non_exempt_encryption" != "false" ]]; then
    printf 'Unexpected export compliance flag: ITSAppUsesNonExemptEncryption=%s\n' "$uses_non_exempt_encryption" >&2
    exit 1
fi

printf 'Archive: %s\n' "$ARCHIVE_PATH"
printf 'IPA: %s\n' "$ipa_path"
printf 'Bundle: %s\n' "$archived_bundle_id"
printf 'Version: %s (%s)\n' "$archived_version" "$archived_build"
printf 'Privacy manifest: present\n'
printf 'Non-exempt encryption: %s\n' "$uses_non_exempt_encryption"
