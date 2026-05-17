# Captain's Log App Store Connect Submission Packet

This is the handoff checklist for the first TestFlight/App Store Connect submission. It points to the current verified artifacts and keeps the remaining external work explicit.

## Current Local State

- Repo: `https://github.com/blakecrosley/CaptainsLog.git`
- Branch: `main`
- Exported app commit: `6846aaa9a4bb079b1d4ec92f478fc841dd9300ea`
- Exported Kit941 commit: `9330d58ca0e14d8133250a9051599fecafea03b2`
- Bundle ID: `com.blakecrosley.captainslog`
- Version/build: `1.0.0 (1)`
- Team ID used by export scripts: `M4WTLM6RAQ`
- Exported IPA: `/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa`
- Export manifest: `/tmp/captainslog-current-appstore-export/Export/ExportManifest.txt`
- Screenshot source: `/tmp/captainslog-key-state-audit`
- Packaged screenshots: `/tmp/captainslog-key-state-packaged`

## Current Verification Evidence

Last local audit: May 17, 2026.

- `Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit` passed: metadata limits, policy/support URL reachability, privacy manifest, export-compliance flag, bundle/build settings, marketing icon, and all iPhone/iPad screenshot dimensions.
- Preflight now checks that the published Privacy Policy and Support pages contain expected Captain's Log, GitHub, Keychain, optional AI provider, and contact content, not just HTTP success.
- `Scripts/privacy_required_reason_audit.sh` is included in preflight and passed for the app target plus local `Kit941` package source.
- `Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export` exported the current IPA from CaptainsLog commit `6846aaa9a4bb079b1d4ec92f478fc841dd9300ea` and Kit941 commit `9330d58ca0e14d8133250a9051599fecafea03b2`, with both source trees clean at export.
- `Scripts/upload_app_store_ipa.sh local-check "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"` passed: bundle `com.blakecrosley.captainslog`, version `1.0.0 (1)`, privacy manifest present, `ITSAppUsesNonExemptEncryption=false`, `get-task-allow=false`, Kit941 commit recorded, Kit941 dirty state `false`, and release debug fixture strings absent.
- `Scripts/upload_app_store_ipa.sh validate "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"` was attempted after the local check passed and is blocked until App Store Connect API credentials are provided: set `APP_STORE_CONNECT_API_KEY` and `APP_STORE_CONNECT_API_ISSUER`.
- Current Git status after the local audit: clean against `origin/main`.
- The commits after `6846aaa9a4bb079b1d4ec92f478fc841dd9300ea` are documentation-only handoff updates. Regenerate the IPA if any app target, source, resource, entitlement, privacy manifest, build setting, package, or signing input changes.
- The export manifest records the local `Kit941` package commit and dirty state because the app links `../941Kit` directly. At export, Kit941 was clean but ahead of its remote by one commit.

## Prompt-To-Artifact Checklist

| Requirement | Artifact | Current Evidence | Status |
| --- | --- | --- | --- |
| Prepare for App Store Connect | `Docs/AppStoreReadiness.md`, this packet | Preflight, archive/export, screenshots, metadata, privacy notes, and upload helper exist; current IPA local check passes from clean CaptainsLog commit `6846aaa9a4bb079b1d4ec92f478fc841dd9300ea` and clean Kit941 commit `9330d58ca0e14d8133250a9051599fecafea03b2` | Locally ready |
| Clean up UI | Fixture screenshot routes and latest PNG audit | Dashboard, Work Map, journal, repositories, AI settings, and Privacy & Data screenshots generated for iPhone and iPad; iPad dashboard uses the adaptive tablet layout; no dashboard sync bar or repository toggle clipping was visible in the checked PNGs | Locally reviewed |
| Make design feel coherent | `.impeccable.md`, fixture screenshots | Current direction is quiet, precise, journal-like, Apple-native, with Work Map carrying identity | Locally reviewed |
| Metadata ready to paste | `Docs/AppStoreMetadata.md` | Name, subtitle, description, keywords, review notes, URLs, screenshot order, privacy draft | Locally ready, legal review open |
| Privacy policy/support ready | `Docs/PrivacyPolicyDraft.md`, `Docs/SupportPageDraft.md`, `Docs/AppStorePrivacyAnswers.md` | URLs passed preflight reachability checks; privacy answers map App Store Connect fields to current code evidence | Locally ready, legal review open |
| Binary export ready | `Scripts/export_app_store_ipa.sh` | Current export produced an IPA with bundle ID `com.blakecrosley.captainslog`, version `1.0.0 (1)`, privacy manifest present, `get-task-allow=false`, encryption flag `false`, and a sibling export manifest with the exact git commit | Locally ready |
| Upload path ready | `Scripts/upload_app_store_ipa.sh` | Local IPA check passes, requires a clean-tree export manifest by default, rejects release builds containing debug screenshot/auth fixture strings, and validate/upload/status require App Store Connect credentials; current validate attempt is blocked by missing API key and issuer env vars | Script ready, external credentials open |
| Screenshots ready | `Scripts/capture_app_store_screenshots.sh`, `Scripts/package_app_store_screenshots.sh` | 12 PNGs generated and packaged for 6.9-inch iPhone and 13-inch iPad upload folders | Locally ready, human marketing acceptance open |
| Physical device smoke | `xcodebuild`, `xcrun devicectl` | Current Debug build installed on the connected iPhone 17 Pro Max and launched successfully with bundle ID `com.blakecrosley.captainslog` | Build/install/launch verified |
| Real data confidence | App runtime with a large GitHub account | Not rerun after latest App Store prep | Open |

## Local Commands Before Upload

Run these from the repo root:

```sh
Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit
Scripts/upload_app_store_ipa.sh local-check "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```

`local-check` intentionally requires the sibling `ExportManifest.txt` created by `Scripts/export_app_store_ipa.sh`, fails dirty-tree exports by default, and fails if the submitted executable contains debug screenshot/auth fixture hooks. Only bypass the manifest/dirty-state checks for legacy IPA inspection:

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

Use the conservative, paste-ready privacy draft in `Docs/AppStorePrivacyAnswers.md`.

Summary:

- Data Used to Track You: no.
- Data Linked to You for App Functionality: GitHub profile name when returned, GitHub login/account identifier, repository names, commit messages, commit metadata, changed file paths, diff stats, generated journal text, and work classifications.
- Data Not Linked to You: none in this build unless App Store Connect requires Apple-provided diagnostics to be handled separately.
- Optional cloud AI: OpenAI and Anthropic receive selected commit evidence only when the user attaches that provider key and generates AI output.
- Pasteboard: the app writes the short-lived GitHub device code only when the user taps "Copy & Open GitHub"; it does not read the pasteboard.

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
- Confirm whether the published Privacy Policy and Support pages should keep the website-level self-hosted analytics script; this is not an app SDK, but it appears in the public page HTML that App Review can inspect.
- Run one real large-account QA pass before submitting for review.
