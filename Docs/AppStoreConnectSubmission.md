# Captain's Log App Store Connect Submission Packet

This is the handoff checklist for the first TestFlight/App Store Connect submission. It points to the current verified artifacts and keeps the remaining external work explicit.

## Current Local State

- Repo: `https://github.com/blakecrosley/CaptainsLog.git`
- Branch: `main`
- Bundle ID: `com.blakecrosley.captainslog`
- Version/build: `1.0.0 (1)`
- Team ID used by export scripts: `M4WTLM6RAQ`
- Exported IPA: `/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa`
- Export manifest: `/tmp/captainslog-current-appstore-export/Export/ExportManifest.txt`
- Screenshot source: `/tmp/captainslog-key-state-audit`
- Packaged screenshots: `/tmp/captainslog-key-state-packaged`

## Prompt-To-Artifact Checklist

| Requirement | Artifact | Current Evidence | Status |
| --- | --- | --- | --- |
| Prepare for App Store Connect | `Docs/AppStoreReadiness.md`, this packet | Preflight, archive/export, screenshots, metadata, privacy notes, and upload helper exist | Locally ready |
| Clean up UI | Fixture screenshot routes and latest PNG audit | Dashboard, Work Map, journal, repositories, AI settings, and Privacy & Data screenshots generated for iPhone and iPad; iPad dashboard uses the adaptive tablet layout | Locally reviewed |
| Make design feel coherent | `.impeccable.md`, fixture screenshots | Current direction is quiet, precise, journal-like, Apple-native, with Work Map carrying identity | Locally reviewed |
| Metadata ready to paste | `Docs/AppStoreMetadata.md` | Name, subtitle, description, keywords, review notes, URLs, screenshot order, privacy draft | Locally ready, legal review open |
| Privacy policy/support ready | `Docs/PrivacyPolicyDraft.md`, `Docs/SupportPageDraft.md` | URLs passed preflight reachability checks | Locally ready, legal review open |
| Binary export ready | `Scripts/export_app_store_ipa.sh` | Current export produced an IPA with bundle ID `com.blakecrosley.captainslog`, version `1.0.0 (1)`, privacy manifest present, `get-task-allow=false`, encryption flag `false`, and a sibling export manifest with the exact git commit | Locally ready |
| Upload path ready | `Scripts/upload_app_store_ipa.sh` | Local IPA check passes, requires a clean-tree export manifest by default, and validate/upload/status require App Store Connect credentials | Script ready, external credentials open |
| Screenshots ready | `Scripts/capture_app_store_screenshots.sh`, `Scripts/package_app_store_screenshots.sh` | 12 PNGs generated and packaged for 6.9-inch iPhone and 13-inch iPad upload folders | Locally ready, human marketing acceptance open |
| Physical device smoke | `xcodebuild`, `xcrun devicectl` | Current Debug build installed on the connected iPhone 17 Pro Max and launched successfully with bundle ID `com.blakecrosley.captainslog` | Build/install/launch verified |
| Real data confidence | App runtime with a large GitHub account | Not rerun after latest App Store prep | Open |

## Local Commands Before Upload

Run these from the repo root:

```sh
Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit
Scripts/upload_app_store_ipa.sh local-check "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```

`local-check` intentionally requires the sibling `ExportManifest.txt` created by `Scripts/export_app_store_ipa.sh` and fails dirty-tree exports by default. Only bypass this for legacy IPA inspection:

```sh
CAPTAINS_LOG_ALLOW_MISSING_EXPORT_MANIFEST=1 Scripts/upload_app_store_ipa.sh local-check "/path/to/legacy.ipa"
CAPTAINS_LOG_ALLOW_DIRTY_EXPORT=1 Scripts/upload_app_store_ipa.sh local-check "/path/to/dirty-export.ipa"
```

If the IPA needs to be regenerated:

```sh
Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
```

If screenshots need to be regenerated:

```sh
Scripts/capture_app_store_screenshots.sh /tmp/captainslog-key-state-audit
Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit
Scripts/package_app_store_screenshots.sh /tmp/captainslog-key-state-audit /tmp/captainslog-key-state-packaged
```

## App Store Connect Record

Create the app record with:

- Platform: iOS
- Name: `Captain's Log`
- Primary language: English (U.S.)
- Bundle ID: `com.blakecrosley.captainslog`
- SKU: `captainslog-ios`
- User access: Full Access unless a narrower App Store Connect team policy is preferred

Use `Docs/AppStoreMetadata.md` for the product page fields.

## Build Upload

Set App Store Connect API credentials in the shell, keeping the `.p8` private key outside the repo:

```sh
export APP_STORE_CONNECT_API_KEY="..."
export APP_STORE_CONNECT_API_ISSUER="..."
export APP_STORE_CONNECT_P8_FILE="/absolute/path/to/AuthKey_....p8"
```

Then validate, upload, and check processing:

```sh
Scripts/upload_app_store_ipa.sh validate "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
Scripts/upload_app_store_ipa.sh upload "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```

After upload, use the delivery ID from `altool` if available:

```sh
export APP_STORE_CONNECT_DELIVERY_ID="..."
Scripts/upload_app_store_ipa.sh status "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```

If a delivery ID is not available, set the App Store Connect Apple ID after the app record exists:

```sh
export APP_STORE_CONNECT_APPLE_ID="..."
Scripts/upload_app_store_ipa.sh status "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```

## Screenshots

Upload the packaged screenshots in this order:

1. `01-dashboard.png`
2. `02-work-map.png`
3. `03-journal.png`
4. `04-repositories.png`
5. `05-ai-providers.png`
6. `06-privacy-data.png`

Use both folders:

- `/tmp/captainslog-key-state-packaged/iphone-6.9`
- `/tmp/captainslog-key-state-packaged/ipad-13`

Do a human pass before submission. The local checks verify size and obvious UI regressions, not marketing quality.

## Physical Device Smoke

The May 17, 2026 local smoke pass used the connected iPhone 17 Pro Max (`00008150-00166D690EF0401C`):

```sh
xcodebuild -project CaptainsLog.xcodeproj -scheme CaptainsLog-iOS -configuration Debug -destination 'id=00008150-00166D690EF0401C' -derivedDataPath /tmp/captainslog-device-derived build
xcrun devicectl device install app --device 2F9ADEAE-BF3B-5E99-BB42-25B09F86C1AC "/tmp/captainslog-device-derived/Build/Products/Debug-iphoneos/Captain's Log.app"
xcrun devicectl device process launch --device 2F9ADEAE-BF3B-5E99-BB42-25B09F86C1AC com.blakecrosley.captainslog
```

Build, install, and launch succeeded on May 17, 2026. The latest launch command reported `Launched application with com.blakecrosley.captainslog bundle identifier.`

## App Privacy Draft

Use the conservative privacy draft in `Docs/AppStoreMetadata.md`:

- User ID: GitHub login/account identifier when signed in.
- Other User Content: repository names, commit messages, commit metadata, changed files, diff stats, and generated journal text.
- Linked to user: yes when tied to the GitHub account or selected repositories.
- Used for tracking: no.
- Used for third-party advertising: no.
- Used for analytics: no in the app code today.
- Shared with third-party AI: only when the user attaches a cloud AI key and generates a journal entry.

Also disclose the user-initiated pasteboard write from GitHub device sign-in if App Store Connect asks about clipboard behavior. Captain's Log writes the short-lived device code only when the user taps "Copy & Open GitHub" and does not read from the pasteboard.

Reasoning from Apple's App Privacy Details guidance (`https://developer.apple.com/app-store/app-privacy-details/`):

- Data collected solely for app functionality still needs to be declared.
- Data processed only on device is not "collected" for App Store privacy answers.
- Captain's Log imports and stores GitHub history locally, but GitHub sign-in/API access and optional cloud AI generation mean the conservative App Functionality disclosure is the safer submission answer.

Legal review is still recommended before final submission.

## App Review Notes

Paste from `Docs/AppStoreMetadata.md`. Key points:

- GitHub sign-in is required because Captain's Log is a client for a specific third-party service.
- The app does not create a separate Captain's Log account.
- Review can use demo data if they do not want to connect GitHub.
- OpenAI/Anthropic keys are optional bring-your-own-key settings.
- Background history indexing should not block the UI.

If App Review needs a live account, create a purpose-built GitHub account with safe demo repositories rather than giving access to a personal account.

## Remaining External Gates

- Create the App Store Connect app record.
- Validate and upload the IPA with App Store Connect credentials.
- Verify TestFlight processing status.
- Make the final screenshot marketing decision.
- Complete legal/privacy review.
- Run one real large-account QA pass before submitting for review.
