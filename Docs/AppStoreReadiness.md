# Captain's Log App Store Readiness

This note tracks the current iOS App Store Connect blockers and the decisions still needed before the first TestFlight or App Review upload.

For the final handoff sequence, use `Docs/AppStoreConnectRunbook.md`. For the full evidence packet, use `Docs/AppStoreConnectSubmission.md`. For the current completion audit, use `Docs/AppStoreCompletionAudit.md`. For App Store Connect privacy answers, use `Docs/AppStorePrivacyAnswers.md`.

## Current Code Evidence

- Bundle ID is `com.blakecrosley.captainslog`; iPhone and iPad are enabled through target family `1,2`; deployment target is iOS 26.0.
- The iOS app uses `UserDefaults` / `@AppStorage` for local preferences, so the bundle includes `CaptainsLog/Resources/PrivacyInfo.xcprivacy` with `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`.
- GitHub Device Flow and API calls go directly to GitHub. OAuth/device URLs and API URLs are in `GitHubAPIClient`.
- Optional cloud AI calls go directly to OpenAI or Anthropic only when the user attaches a provider key.
- Tokens and cloud AI keys are stored on-device in Keychain.
- The app does not import CryptoKit, CommonCrypto, or custom cryptography APIs. Current network calls use system `URLSession` over HTTPS for GitHub, OpenAI, Anthropic, and the published support/privacy links.
- `CaptainsLog/App/CaptainsLog-iOS-Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false` for App Store Connect export-compliance prompts. Revisit this if custom encryption, VPN, secure messaging, file encryption, or other cryptographic functionality is added.
- The repo contains an app icon asset catalog. `Scripts/capture_app_store_screenshots.sh` captures repeatable iPhone and iPad screenshots with a neutral fixture identity for dashboard, Work Map, journal, repositories, AI settings, and Privacy & Data. The screenshot fixture seeds a fake debug-only OpenAI key so the AI settings and privacy screens show the intended attached-key state without exposing a real secret.
- A local generic iOS archive succeeds with Xcode 26.5 and includes `PrivacyInfo.xcprivacy`, `Assets.car`, `AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`, and `ITSAppUsesNonExemptEncryption=false`.
- The local toolchain currently satisfies Apple's April 28, 2026 upload requirement for iOS and iPadOS apps: Apple requires Xcode 26 or later with the iOS and iPadOS 26 SDK or later, and `xcodebuild -version` reports Xcode 26.5 while `xcodebuild -showsdks` lists iOS 26.5.
- The last successful App Store Connect export is stale after the app icon resource update in CaptainsLog commit `638fee384b1c03f49770f1581f470f28a5259f37`. Export now fails fast before archiving because local Xcode cannot find an Apple Distribution/iOS Distribution signing identity for team `M4WTLM6RAQ` and App Store Connect API-key env vars are not set for xcodebuild provisioning updates. A bypassed-precheck attempt archived the generic iOS app with Apple Development signing, then `xcodebuild -exportArchive` failed with `No Accounts` and `No signing certificate "iOS Distribution" found`. Regenerate `/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa` after App Store Connect API-key auth or account/distribution signing is available.
- A recent Debug build succeeds for the connected iPhone 17 Pro Max running iOS 26.4.2, installs through `xcrun devicectl`, and launches with bundle ID `com.blakecrosley.captainslog`. The latest May 18, 2026 current-head physical-device UI-test attempt used `/tmp/captainslog-current-device-uitests-live`, built and code signed the app plus test runner with Apple Development, then stopped at `Unlock Blake's iPhone 17 Pro Max (current) to Continue`; the waiting run was interrupted after the destination remained locked. Final Work Map polish verification is therefore simulator, screenshot, export, and preflight based rather than fresh physical-device UI-test based.
- The latest screenshot audit generated 12 clean PNGs with no previous-app breadcrumb: iPhone 17 Pro Max at `1320x2868` and iPad Pro 13 portrait at `2064x2752`, matching Apple's accepted 6.9-inch iPhone and 13-inch iPad screenshot sizes. The screenshot preflight, package, and readiness scripts also accept Apple's 13-inch iPad landscape size `2752x2064` if a later human marketing pass chooses landscape iPad screenshots instead. The May 18, 2026 output in `/tmp/captainslog-key-state-audit` opens the dashboard on a fuller fixture week, shows the compact selected-period menu instead of a second full-width segmented control, shows the AI settings attached-key state with a fake demo key, uses adaptive iPad layouts for Work Map, repository access, AI provider, and Privacy & Data detail pages, adds a selected-day journal preview to the iPad dashboard, and packages into `/tmp/captainslog-key-state-packaged`. Readiness verifies the packaged upload filenames and dimensions. `Scripts/audit_app_store_screenshot_text.sh /tmp/captainslog-key-state-packaged` runs a repeatable Vision OCR pass over the packaged screenshots and found no `fixture`, `UI Fixture`, debug, simulator, sync-progress, error, personal-account, or token-like text.
- A connected-device store audit now exists at `Scripts/audit_device_store.sh`. The May 17, 2026 run copied the app's local SwiftData store from Blake's iPhone 17 Pro Max, passed SQLite integrity, and reported aggregate coverage only: 104 selected repositories, 12,468 commits from 2012-08-16 through 2026-05-17, 12,468/12,468 commits with diff stats, 0 diff-stat errors, 67,479,776 known changed lines, and 137/137 active days from 2026-01-01 through 2026-05-17. This verifies local device-store coverage, not external GitHub API parity.
- Connected-device UI tests on Blake's iPhone 17 Pro Max previously passed 2 tests with 0 failures, but the latest current-head connected-phone attempt was blocked by the locked device before launch. The latest current-head simulator refresh used the iOS 26.5 iPhone 17 destination `277C8808-F02C-43A4-8B4A-11BA187F0788` and passed 69 unit tests plus 3 `CaptainsLogUITests` UI tests with 0 failures, covering first-run Sign in with GitHub and Use Demo Data actions, the production Use Demo Data tap-through into dashboard and journal detail, fixture dashboard launch, Settings, Privacy & Data, and selected-day journal detail.
- A Release simulator build on the iOS 26.5 iPhone 17 destination succeeded from current source at `/tmp/captainslog-demo-path-release`, and a string scan of the built executable found no debug/test fixture strings that would be rejected by the future IPA local check, including screenshot hooks, debug OpenAI key seeding hooks, UI-testing hooks, and the screenshot demo key. Bundle metadata reported bundle ID `com.blakecrosley.captainslog`, version `1.0.0 (1)`, `ITSAppUsesNonExemptEncryption=false`, and `PrivacyInfo.xcprivacy` present. The signed App Store IPA local check still must run after distribution export succeeds.
- The latest `Scripts/app_store_readiness_status.sh` run passed preflight and the credential-guard self-test from clean source, but failed local readiness because the current IPA and export manifest are missing after the blocked clean export. IPA local-check is skipped until a current IPA exists. The script still confirms no App Store Connect `.p8` private-key material is inside the repo. Candidate `AuthKey_*.p8` files are staged outside the repo under `~/.appstoreconnect/private_keys` with owner-only permissions, but the selected key ID and issuer UUID still need to be provided before export/upload credentials are usable. The script reports external App Store Connect credentials, app record, manual fields including Apple Vision Pro and Apple Silicon Mac availability, upload/TestFlight, screenshot acceptance, legal review, and final real-account tap-through as open gates.
- A refreshed current-head generic iOS Release archive with signing disabled succeeded on May 18, 2026 at `/tmp/captainslog-current-nosign-archive-refresh.xcarchive`. This verifies that the current source, resources, and linked `Kit941` package still archive for device with Xcode 26.5. The archived app metadata reported bundle ID `com.blakecrosley.captainslog`, version `1.0.0 (1)`, `DTSDKName=iphoneos26.5`, `MinimumOSVersion=26.0`, `ITSAppUsesNonExemptEncryption=false`, `PrivacyInfo.xcprivacy` present, and `Assets.car` present. This is compile/package evidence only; it is not a signed App Store IPA and does not close the distribution-signing or IPA local-check gates.
- A compatible Apple Vision Pro path now has local evidence: the iOS target reports `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD=YES`, a Release build succeeded for a visionOS 26.5 simulator destination, `xcrun simctl install` installed the app, `xcrun simctl launch` returned process `87848` for `com.blakecrosley.captainslog`, and a simulator screenshot was written to `/tmp/captainslog-vision-launch.png` at `3840x2160`. This proves the compatible iPhone/iPad app launches on a Vision Pro simulator; it does not prove native visionOS, TestFlight processing, review metadata, or full Vision UX acceptance.
- A native macOS target exists with bundle ID `com.blakecrosley.captainslog.mac`, hardened runtime enabled, and deployment target macOS 26.0. A no-sign Release build for `CaptainsLog-macOS` succeeded on May 18, 2026 at `/tmp/captainslog-macos-release-build`; the built app reports version `1.0.0 (1)`, SDK `macosx26.5`, and category `public.app-category.developer-tools`. A local launch smoke test opened that app and produced process `8906`, then quit it cleanly. `codesign -dv` still reports an ad-hoc/linker signature with no team identifier, so Mac App Store signing/export, screenshots, metadata, TestFlight, and human QA remain open.
- No Apple Watch or Apple TV app is ready for this release. `xcodebuild -list` currently shows only `CaptainsLog-iOS`, `CaptainsLog-macOS`, `CaptainsLogTests`, and `CaptainsLogUITests`; the only `tvOS` source hit is shared conditional clipboard code, not a tvOS app target, and there is no watchOS target or scheme.

## App Store Connect Checklist

### Build And Signing

- Create the App Store Connect app record with bundle ID `com.blakecrosley.captainslog`.
- Confirm automatic signing uses team `M4WTLM6RAQ`.
- Use version `1.0.0`, build `1` for the first upload, then increment build numbers for later uploads.
- Confirm export compliance in App Store Connect matches the binary: this build declares no non-exempt encryption in Info.plist and only uses Apple system networking/TLS. The May 17, 2026 archive at `/tmp/CaptainsLog-ExportCompliance.xcarchive` confirmed `ITSAppUsesNonExemptEncryption=false` in the archived app bundle.
- Run `Scripts/app_store_preflight.sh <screenshot-dir>` to check metadata limits, published policy/support URL reachability and expected page content, source privacy/export flags, background-processing task identifier consistency, build settings, app icon size, app icon alpha channels, and iPhone/iPad screenshot dimensions before uploading.
- `Scripts/app_store_preflight.sh` also runs `Scripts/privacy_required_reason_audit.sh`, which scans the app target and local `Kit941` package source for Apple's required reason API categories and fails if source usage is not represented in `PrivacyInfo.xcprivacy`.
- Run `Scripts/export_app_store_ipa.sh` to archive the iOS target, export an App Store Connect IPA, and confirm bundle ID, version/build, privacy manifest presence, and `ITSAppUsesNonExemptEncryption=false`. The script first checks for Xcode 26 or later, an iOS 26 or newer SDK, and either an Apple Distribution/iOS Distribution signing identity for team `M4WTLM6RAQ` or the App Store Connect API key/issuer/`.p8` env vars needed for xcodebuild provisioning updates. It then stages archive, IPA, and export manifest output and only replaces the current IPA folder after export validation and manifest creation succeeds.
- The export manifest records both the CaptainsLog git commit and the local `../941Kit` package git commit/dirty state because Kit941 is compiled directly into the app.
- Run `Scripts/app_store_readiness_status.sh` before submission-day work. It checks the current local packet, fails if CaptainsLog is dirty, fails if the linked Kit941 package source is dirty, reports any CaptainsLog or Kit941 upstream drift, and prints the next external App Store Connect actions after local readiness passes.
- Export with App Store distribution signing before upload. Use `Scripts/app_store_signing_status.sh` to inspect the local signing state before regenerating the IPA. The now-stale May 17, 2026 local export used `method=app-store-connect`, `destination=export`, automatic signing, and produced an IPA with `get-task-allow=false` plus a sibling `ExportManifest.txt` for source traceability. Those artifacts are no longer current and must be regenerated after signing is available.
- Run `Scripts/upload_app_store_ipa.sh local-check <ipa>` before uploading. The local check requires the sibling `ExportManifest.txt`, rejects dirty-tree exports unless explicitly bypassed for legacy inspection, and fails if the submitted executable contains debug/test fixture strings, including screenshot hooks and UI-testing launch hooks. When App Store Connect API credentials are available, run `Scripts/upload_app_store_ipa.sh providers`, set `APP_STORE_CONNECT_PROVIDER_PUBLIC_ID`, then run `Scripts/upload_app_store_ipa.sh app-record` to verify the App Store Connect app record by bundle ID, followed by `Scripts/upload_app_store_ipa.sh validate <ipa>` and `Scripts/upload_app_store_ipa.sh upload <ipa>`. The script uses `xcrun altool` with API key authentication and keeps credentials in environment variables or Apple's supported private-key file locations outside the repo.
- Screenshot packaging and screenshot-review generation now use staged temporary output before replacing the current upload/review folders, so a failed screenshot regeneration should not delete the last approved package or contact sheet.
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
- Manual App Store Connect choices are documented in `Docs/AppStoreMetadata.md`: price the first submission as free, use public App Store distribution, resolve any region-specific availability prompts or narrow availability, make the compatible iPhone/iPad app available on Apple Vision Pro after final smoke-test acceptance, opt out of Apple Silicon Mac availability unless a Mac/TestFlight pass is completed and accepted, choose manual release for version 1.0, complete the age-rating questionnaire from the final binary, use Apple's standard EULA unless legal provides a custom one, mark Made for Kids as no, keep the regulated-medical-device answer as no/not applicable for the current binary, keep the App Store software tax category unless tax/legal review changes it, leave Labels and Markings URLs blank unless legal/product has a required labeling URL, confirm the EU Digital Services Act trader-status answer if EU availability remains enabled, and enter private App Review contact/demo-account/trader contact details only inside App Store Connect. Confirm the final content-rights answer before submission because the app displays user-authorized GitHub repository content.
- Accessibility Nutrition Labels are optional product-page metadata for the first release unless App Store Connect requires them at submission time. Do not publish support claims for VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, or Reduced Motion until common tasks have been tested on each claimed device family.
- Screenshots: Apple requires at least one and up to ten screenshots per device family. Run `Scripts/capture_app_store_screenshots.sh`, verify with `Scripts/app_store_preflight.sh <screenshot-dir>`, then run `Scripts/package_app_store_screenshots.sh <screenshot-dir> /tmp/captainslog-key-state-packaged` to create numbered iPhone and iPad upload folders and `Scripts/make_app_store_screenshot_contact_sheet.sh /tmp/captainslog-key-state-packaged /tmp/captainslog-appstore-review` to refresh the review page/contact sheet. The recommended order is dashboard, Work Map, journal detail, repository access, AI provider settings, then Privacy & Data. The May 18, 2026 audit output in `/tmp/captainslog-key-state-audit` passed preflight after the iPad dashboard journal preview, Work Map height polish, compact dashboard period-control polish, and repository access iPad split, but final marketing acceptance still needs human review.

### Privacy

App Store Connect privacy answers should disclose the actual user data flow:

- GitHub account identity, profile name when returned, and repository/commit metadata are accessed from GitHub for app functionality.
- OAuth tokens and provider API keys are stored locally in Keychain.
- Journal generation uses Apple Foundation Models on-device when available.
- If the user attaches OpenAI or Anthropic keys, selected commit/work context is sent directly to that provider for app functionality.
- No advertising, third-party tracking, or analytics SDK is present in the repo today.

The paste-ready privacy questionnaire draft is in `Docs/AppStorePrivacyAnswers.md`.

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
- Dashboard uses a compact single-column layout on iPhone and an adaptive tablet layout on iPad that keeps the Work Map and selected-period summary visible together, with Day/Week/Month/Year tucked into a compact header menu instead of a second full-width segmented control.
- Empty and partial-data states explain "today has not been refreshed", history indexing, and line-stat coverage from the dashboard sync popover.
- Journal detail now reads like a daily note first, with numbered memorable points, tags, model/source metadata, and commits/diffs available as supporting evidence.
- Screenshot mode has stable fixture routes for dashboard, Work Map, journal detail, repository access, AI provider settings, and Privacy & Data.
- Repository management has fixture-reviewed search, bulk selection, selected/hidden filtering, GitHub access CTAs, and an iPad split layout that keeps controls beside the long repository list.
- Privacy & Data includes direct published Privacy Policy and Support links.
- The May 18, 2026 screenshot audit covered iPhone and iPad dashboard, Work Map, journal, repositories, AI provider settings, and Privacy & Data. No `Kit941 Playground` breadcrumb or repository toggle clipping was visible in the checked PNGs, the dashboard now opens on a fuller fixture week and richer 52-week Work Map, the iPad dashboard fills the portrait frame with a selected-day journal preview, repository access uses a split summary/search plus list layout on iPad, the AI provider screenshot shows the attached-key UI instead of an empty disabled form, and the iPad detail screenshots use wider/two-column layouts where the content naturally splits. The visible demo journal copy no longer includes test-fixture wording.
- `Docs/AppStoreDesignReview.md` records the current design verdict: locally acceptable for the first App Store Connect screenshot pass, with the Work Map carrying product identity and no major new feature work recommended before first TestFlight.
- Debug-only UI performance probes and UI-testing launch hooks are compiled out of the release path; the May 18 Release simulator executable string scan from `/tmp/captainslog-demo-path-release` found no debug/test fixture strings. Direct IPA string inspection remains required after the signed App Store IPA is regenerated.
- The real-account device store can be aggregate-audited without exposing commit messages or repository names by running `Scripts/audit_device_store.sh /tmp/captainslog-device-store-script-audit`.
- The reviewer/demo path has a simulator UI test pass for the production "Use Demo Data" action into dashboard and journal detail, plus an earlier device UI test pass for first-run actions, fixture dashboard, settings, privacy, and selected-day journal detail.
- The `blakecrosley.com` source PR that disables active analytics scripts on the Captain's Log Privacy Policy and Support pages was merged on May 17, 2026 as merge commit `661f0a183bf8ed8dca22f80ff83315df90f1f819`.

### Next

- A final manual tap-through on the real large GitHub account is still recommended before submission, even though local device-store coverage now has aggregate evidence.
- Manual App Store Connect fields still need to be entered and checked for missing-metadata warnings in App Store Connect, including region-specific availability prompts if shown, Apple Vision Pro availability, Apple Silicon Mac availability, the EU DSA trader-status declaration if EU availability remains enabled, Labels and Markings URLs if shown, the regulated-medical-device declaration if shown, and tax category if shown.
- Accessibility Nutrition Labels can remain not yet indicated for the first release, but a per-device accessibility evaluation should happen before publishing any support claims.
- Final App Store screenshot marketing acceptance still needs human review on the packaged iPhone and iPad exports. The readiness script checks that the contact sheet, review page, and review checklist exist, but a person still needs to approve that the screenshots are private-data safe, free of debug UI and clipped controls, and not generic analytics-dashboard work.
- Legal review of the published privacy copy is still recommended before App Store Connect submission.
- `Docs/AppStoreConnectSubmission.md` contains the closeout table for the remaining external gates, including the exact evidence needed to close each gate.

## Official References

- Add a new app record: https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- Submitting apps: https://developer.apple.com/app-store/submitting/
- Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- App Store Connect API: https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api
- Set app age rating: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/
- Age rating values and definitions: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- Accessibility Nutrition Labels overview: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/
- Manage Accessibility Nutrition Labels: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels/
- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Manage app privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- App information fields: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Platform version fields: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Pricing and availability: https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-pricing-and-availability
- Set app price: https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price
- Version release option: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/
- Apple Vision Pro availability: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-apple-vision-pro
- Apple Silicon Mac availability: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon/
- EU Digital Services Act trader requirements: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
- Declare regulated medical device status: https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status/
- Set a tax category: https://developer.apple.com/help/app-store-connect/manage-app-information/set-a-tax-category
- Screenshots: https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- App icon: https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon/
- Review guidelines: https://developer.apple.com/app-store/review/guidelines/
- Privacy manifest files: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
