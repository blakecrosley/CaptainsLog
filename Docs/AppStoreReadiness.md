# Captain's Log App Store Readiness

This note tracks the current iOS App Store Connect blockers and the decisions still needed before the first TestFlight or App Review upload.

## Current Code Evidence

- Bundle ID is `com.blakecrosley.captainslog`; iPhone and iPad are enabled through target family `1,2`; deployment target is iOS 26.0.
- The iOS app uses `UserDefaults` / `@AppStorage` for local preferences, so the bundle includes `CaptainsLog/Resources/PrivacyInfo.xcprivacy` with `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`.
- GitHub Device Flow and API calls go directly to GitHub. OAuth/device URLs and API URLs are in `GitHubAPIClient`.
- Optional cloud AI calls go directly to OpenAI or Anthropic only when the user attaches a provider key.
- Tokens and cloud AI keys are stored on-device in Keychain.
- The repo contains an app icon asset catalog. `Scripts/capture_app_store_screenshots.sh` captures repeatable iPhone and iPad screenshots with a neutral fixture identity for dashboard, Work Map, journal, repositories, AI settings, and Privacy & Data.
- A local generic iOS archive succeeds and includes `PrivacyInfo.xcprivacy`, `Assets.car`, `AppIcon60x60@2x.png`, and `AppIcon76x76@2x~ipad.png`. The latest archive was signed with an Apple Development profile, so App Store distribution export/upload is still unverified.

## App Store Connect Checklist

### Build And Signing

- Create the App Store Connect app record with bundle ID `com.blakecrosley.captainslog`.
- Confirm automatic signing uses team `M4WTLM6RAQ`.
- Use version `1.0.0`, build `1` for the first upload, then increment build numbers for later uploads.
- Archive the iOS target and confirm the privacy manifest is included in the archive.
- Export or upload with App Store distribution signing. The local archive check used `Apple Development: Christopher Crosley (5U69CE2KAT)` and `get-task-allow=true`, which is not the final App Store signing state.

### Product Page

- Name: `Captain's Log`.
- Subtitle: candidate copy is in `Docs/AppStoreMetadata.md`; keep it under 30 characters.
- Primary category recommendation: Developer Tools.
- Description: candidate copy is in `Docs/AppStoreMetadata.md`; explain the product as a private GitHub history journal, not a productivity scorekeeper.
- Keywords: candidate copy is in `Docs/AppStoreMetadata.md`; avoid company or app names in the keyword field.
- Support URL: required before submission. Draft page content is in `Docs/SupportPageDraft.md`; it still needs a real contact path and live URL verification.
- Privacy Policy URL: required for iOS and macOS apps. Draft policy content is in `Docs/PrivacyPolicyDraft.md`; it still needs final contact information, legal review, and live URL verification.
- Screenshots: Apple requires at least one and up to ten screenshots per device family. Run `Scripts/capture_app_store_screenshots.sh` and review the exported dashboard, Work Map, journal detail, repository access, AI provider, and Privacy & Data captures before upload.

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

### Next

- Repository management still needs final on-device review for long real account lists, search, select all, and the GitHub access CTA.
- Final App Store screenshot selection still needs human review on iPhone and iPad exports.
- Support and privacy URLs must be live and verified before App Store Connect submission.

## Official References

- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Manage app privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- App information fields: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Platform version fields: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Screenshots: https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- App icon: https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon/
- Review guidelines: https://developer.apple.com/app-store/review/guidelines/
- Privacy manifest files: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
