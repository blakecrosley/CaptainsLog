# Captain's Log App Store Readiness

This note tracks the current iOS App Store Connect blockers and the decisions still needed before the first TestFlight or App Review upload.

## Current Code Evidence

- Bundle ID is `com.blakecrosley.captainslog`; iPhone and iPad are enabled through target family `1,2`; deployment target is iOS 26.0.
- The iOS app uses `UserDefaults` / `@AppStorage` for local preferences, so the bundle includes `CaptainsLog/Resources/PrivacyInfo.xcprivacy` with `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`.
- GitHub Device Flow and API calls go directly to GitHub. OAuth/device URLs and API URLs are in `GitHubAPIClient`.
- Optional cloud AI calls go directly to OpenAI or Anthropic only when the user attaches a provider key.
- Tokens and cloud AI keys are stored on-device in Keychain.
- The app does not import CryptoKit, CommonCrypto, or custom cryptography APIs. Current network calls use system `URLSession` over HTTPS for GitHub, OpenAI, Anthropic, and the published support/privacy links.
- `CaptainsLog/App/CaptainsLog-iOS-Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false` for App Store Connect export-compliance prompts. Revisit this if custom encryption, VPN, secure messaging, file encryption, or other cryptographic functionality is added.
- The repo contains an app icon asset catalog. `Scripts/capture_app_store_screenshots.sh` captures repeatable iPhone and iPad screenshots with a neutral fixture identity for dashboard, Work Map, journal, repositories, AI settings, and Privacy & Data.
- A local generic iOS archive succeeds with Xcode 26.5 and includes `PrivacyInfo.xcprivacy`, `Assets.car`, `AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`, and `ITSAppUsesNonExemptEncryption=false`.
- A local App Store Connect export succeeds with automatic signing. The exported IPA is signed by `Apple Distribution: Christopher Crosley (M4WTLM6RAQ)`, uses `get-task-allow=false`, includes symbols, and keeps the privacy manifest in the app bundle. Upload to App Store Connect/TestFlight is still unverified.
- The latest screenshot audit generated 12 clean PNGs with no previous-app breadcrumb: iPhone 17 Pro Max at `1320x2868` and iPad Pro 13 at `2064x2752`, matching Apple's accepted 6.9-inch iPhone and 13-inch iPad portrait screenshot sizes.

## App Store Connect Checklist

### Build And Signing

- Create the App Store Connect app record with bundle ID `com.blakecrosley.captainslog`.
- Confirm automatic signing uses team `M4WTLM6RAQ`.
- Use version `1.0.0`, build `1` for the first upload, then increment build numbers for later uploads.
- Confirm export compliance in App Store Connect matches the binary: this build declares no non-exempt encryption in Info.plist and only uses Apple system networking/TLS. The May 17, 2026 archive at `/tmp/CaptainsLog-ExportCompliance.xcarchive` confirmed `ITSAppUsesNonExemptEncryption=false` in the archived app bundle.
- Run `Scripts/app_store_preflight.sh <screenshot-dir>` to check metadata limits, published policy/support URLs, source privacy/export flags, build settings, app icon size, and iPhone/iPad screenshot dimensions before uploading.
- Run `Scripts/export_app_store_ipa.sh` to archive the iOS target, export an App Store Connect IPA, and confirm bundle ID, version/build, privacy manifest presence, and `ITSAppUsesNonExemptEncryption=false`.
- Export with App Store distribution signing before upload. The May 17, 2026 local export used `method=app-store-connect`, `destination=export`, automatic signing, and produced `/tmp/CaptainsLog-AppStoreExport/Captain's Log.ipa` with `get-task-allow=false`.
- Upload the exported build to App Store Connect/TestFlight and verify processing status.

### Product Page

- Name: `Captain's Log`.
- Subtitle: candidate copy is in `Docs/AppStoreMetadata.md`; keep it under 30 characters.
- Primary category recommendation: Developer Tools.
- Description: candidate copy is in `Docs/AppStoreMetadata.md`; explain the product as a private GitHub history journal, not a productivity scorekeeper.
- Keywords: candidate copy is in `Docs/AppStoreMetadata.md`; avoid company or app names in the keyword field.
- Support URL: `https://blakecrosley.com/captains-log/support` is live and includes the support contact path `blake@941apps.com`.
- Privacy Policy URL: `https://blakecrosley.com/captains-log/privacy` is live and includes the privacy contact path `blake@941apps.com`. Legal review is still recommended before App Review submission.
- The in-app Privacy & Data screen links to the published Privacy Policy and Support pages so users and App Review can reach the same public documents from inside the app.
- Screenshots: Apple requires at least one and up to ten screenshots per device family. Run `Scripts/capture_app_store_screenshots.sh`, verify with `Scripts/app_store_preflight.sh <screenshot-dir>`, then run `Scripts/package_app_store_screenshots.sh <screenshot-dir>` to create numbered iPhone and iPad upload folders. The recommended order is dashboard, Work Map, journal detail, repository access, AI provider settings, then Privacy & Data. The May 17, 2026 audit output in `/tmp/captainslog-repo-search-audit` passed preflight after the repository search placement polish, but final marketing acceptance still needs human review.

### Privacy

App Store Connect privacy answers should disclose the actual user data flow:

- GitHub account identity and repository/commit metadata are accessed from GitHub for app functionality.
- OAuth tokens and provider API keys are stored locally in Keychain.
- Journal generation uses Apple Foundation Models on-device when available.
- If the user attaches OpenAI or Anthropic keys, selected commit/work context is sent directly to that provider for app functionality.
- No advertising, third-party tracking, or analytics SDK is present in the repo today.

The in-app Privacy & Data screen now explains GitHub revocation, AI key removal, and the Clear Imported History action for local commits, line stats, and journals.

### Review Notes

Explain that GitHub sign-in is required because the app is a client for a specific third-party service and users must sign in to GitHub to access their repository content. Apple guideline 4.8 has an exception for this shape, but the note should be explicit to avoid a generic "missing Sign in with Apple" rejection.

Also include:

- A test GitHub account or demo-data instructions if review cannot access a repository.
- That OpenAI/Anthropic keys are optional bring-your-own-key settings and not required for core on-device journal generation.
- That background processing indexes older Git history in batches and should not block the UI.

## UI / Product Readiness

The product direction should stay quiet, precise, and journal-like. Current status before final screenshot selection:

### Done

- First-run path now presents GitHub connect and demo-data choices as a clean setup screen.
- Empty and partial-data states explain "today has not been refreshed", history indexing, and line-stat coverage from the dashboard sync popover.
- Journal detail now reads like a daily note first, with numbered memorable points, tags, model/source metadata, and commits/diffs available as supporting evidence.
- Screenshot mode has stable fixture routes for dashboard, Work Map, journal detail, repository access, AI provider settings, and Privacy & Data.
- Repository management has fixture-reviewed search, bulk selection, selected/hidden filtering, and GitHub access CTAs.
- Privacy & Data includes direct published Privacy Policy and Support links.
- The May 17, 2026 screenshot audit covered iPhone and iPad dashboard, Work Map, journal, repositories, AI provider settings, and Privacy & Data. No `Kit941 Playground` breadcrumb or repository toggle clipping was visible in the checked PNGs.

### Next

- A final pass on a real large GitHub account is still recommended before submission.
- Final App Store screenshot marketing acceptance still needs human review on the packaged iPhone and iPad exports.
- Legal review of the published privacy copy is still recommended before App Store Connect submission.

## Official References

- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Manage app privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- App information fields: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Platform version fields: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Screenshots: https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- App icon: https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon/
- Review guidelines: https://developer.apple.com/app-store/review/guidelines/
- Privacy manifest files: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
