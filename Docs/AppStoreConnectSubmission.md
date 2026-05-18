# Captain's Log App Store Connect Submission Packet

This is the handoff checklist for the first TestFlight/App Store Connect submission. It points to the current verified artifacts and keeps the remaining external work explicit.

## Current Local State

- Repo: `https://github.com/blakecrosley/CaptainsLog.git`
- Branch: `main`
- Exported app commit: `0485480d8d37fbba5f6e1437a54d3bc0d50c1733`
- Exported Kit941 commit: `9330d58ca0e14d8133250a9051599fecafea03b2`
- Bundle ID: `com.blakecrosley.captainslog`
- Version/build: `1.0.0 (1)`
- Team ID used by export scripts: `M4WTLM6RAQ`
- Exported IPA: `/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa`
- Export manifest: `/tmp/captainslog-current-appstore-export/Export/ExportManifest.txt`
- Screenshot source: `/tmp/captainslog-key-state-audit`
- Packaged screenshots: `/tmp/captainslog-key-state-packaged`
- Design review: `Docs/AppStoreDesignReview.md`

## Current Verification Evidence

Last local audit: May 17, 2026.

- `Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit` passed: metadata limits, policy/support URL reachability, privacy manifest, export-compliance flag, bundle/build settings, marketing icon, and all iPhone/iPad screenshot dimensions.
- `xcodebuild test -project CaptainsLog.xcodeproj -scheme CaptainsLog-iOS -destination 'id=00119EA5-FDF1-4F0B-A47F-5ADB10AD6BA3' -only-testing:CaptainsLogTests` passed 69 unit tests with 0 failures.
- `xcodebuild test -project CaptainsLog.xcodeproj -scheme CaptainsLog-iOS -destination 'id=00119EA5-FDF1-4F0B-A47F-5ADB10AD6BA3' -only-testing:CaptainsLogUITests` passed 2 UI tests with 0 failures after the final Work Map height polish. This covers first-run primary actions, fixture dashboard launch, settings navigation, Privacy & Data, and selected-day journal detail on the simulator.
- A connected-phone `CaptainsLogUITests` run previously passed 2 UI tests with 0 failures on Blake's iPhone 17 Pro Max. A post-polish connected-phone rerun was attempted but stopped at `Unlock Blake's iPhone 17 Pro Max (current) to Continue`, so the final Work Map polish is simulator, screenshot, export, and preflight verified rather than fresh physical-device UI-test verified.
- Preflight now checks that the published Privacy Policy and Support pages contain expected Captain's Log, GitHub, Keychain, optional AI provider, and contact content, not just HTTP success.
- Preflight now warns only when the published Privacy Policy or Support page includes active analytics script endpoints, not when the privacy copy says the app has no analytics SDKs. The current live pages passed the active-analytics check on May 17, 2026. The matching `blakecrosley.com` source PR was merged on May 17, 2026 as merge commit `661f0a183bf8ed8dca22f80ff83315df90f1f819`: https://github.com/blakecrosley/blakecrosley-site/pull/15
- `Scripts/privacy_required_reason_audit.sh` is included in preflight and passed for the app target plus local `Kit941` package source.
- `CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export` exported the current IPA from CaptainsLog commit `0485480d8d37fbba5f6e1437a54d3bc0d50c1733` and Kit941 commit `9330d58ca0e14d8133250a9051599fecafea03b2`, with both source trees clean at export.
- `Scripts/upload_app_store_ipa.sh local-check "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"` passed: bundle `com.blakecrosley.captainslog`, version `1.0.0 (1)`, privacy manifest present, `ITSAppUsesNonExemptEncryption=false`, `get-task-allow=false`, Kit941 commit recorded, Kit941 dirty state `false`, and release debug fixture strings absent.
- Direct IPA string inspection found no debug UI performance probe strings in the exported release executable.
- `Scripts/upload_app_store_ipa.sh validate "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"` was attempted against the current IPA after the local check passed and is blocked until App Store Connect API credentials are provided: set `APP_STORE_CONNECT_API_KEY` and `APP_STORE_CONNECT_API_ISSUER`.
- `xcodebuild build -project CaptainsLog.xcodeproj -scheme CaptainsLog-iOS -destination 'id=00008150-00166D690EF0401C'` previously built a Debug app for Blake's iPhone 17 Pro Max, then `xcrun devicectl device install app` installed bundle `com.blakecrosley.captainslog` and `xcrun devicectl device process launch` launched it successfully with process id `6545`.
- `Scripts/audit_device_store.sh /tmp/captainslog-device-store-script-audit` copied the connected iPhone app store and passed SQLite integrity. Aggregate-only output reported 1 account, 104 selected repositories, 12,468 commits from 2012-08-16 through 2026-05-17, 12,468/12,468 commits with diff stats, 0 diff-stat errors, 67,479,776 known changed lines, and 137/137 active days from 2026-01-01 through 2026-05-17. This is local device-store coverage evidence, not an external GitHub API parity proof.
- Current Git status after the local audit: clean against `origin/main`.
- Regenerate the IPA if any app target, source, resource, entitlement, privacy manifest, build setting, package, or signing input changes.
- The export manifest records the local `Kit941` package commit and dirty state because the app links `../941Kit` directly. At export, Kit941 was clean and aligned with `origin/main`.

## Official Docs Cross-Check

Checked against Apple documentation on May 18, 2026.

- Apple says to create the App Store Connect app record before uploading a build. Required roles are Account Holder, App Manager, or Admin, and the record opens in `Prepare for Submission` after creation. This matches the remaining app-record gate below.
- Apple says builds can be uploaded with Xcode, altool, or Transporter after an app is added to the account. It also notes that the first upload creates a beta version but the build must finish Apple processing before it appears in App Store Connect. This matches the validate, upload, and TestFlight-processing gates below.
- Apple says team API keys require Account Holder or Admin, and downloaded API keys are private and only downloadable once. This matches the `.p8` handling below: keep `AuthKey_*.p8` outside the repo and pass it through `APP_STORE_CONNECT_P8_FILE`.
- Apple's screenshot specification allows one to ten `.jpeg`, `.jpg`, or `.png` screenshots. The current packaged set has six PNGs per family. The iPhone 6.9-inch portrait size `1320 x 2868` and iPad 13-inch portrait size `2064 x 2752` are accepted sizes in Apple's table.
- Apple says to answer age-rating questions from the app's content and capabilities. Its values and definitions include capabilities such as user-generated content and unrestricted web access, plus content categories such as medical information, mature themes, violence, gambling, contests, and advertising. This matches the manual age-rating draft in `Docs/AppStoreMetadata.md`.
- Apple says pricing and availability determine where and when an app is available and at what price, and that a price must be set before App Review submission. This matches the manual first-submission value in `Docs/AppStoreMetadata.md`: free app, public distribution, broadly available unless legal review narrows it.
- Apple says App Review information includes a contact name, email, phone number, notes, and demo account information if login is required. This matches the remaining human-only App Review contact and safe GitHub demo-account gate below.
- Apple says each App Store version can be released manually, automatically after approval, or automatically no earlier than a specified date. The recommended first-submission value is manual release so approval does not automatically publish version 1.0.
- Apple says App Store privacy information is required for new apps and updates. This matches the open legal/privacy review gate and the paste-ready privacy questionnaire in `Docs/AppStorePrivacyAnswers.md`.
- Local Xcode evidence: `xcrun altool --help` reports altool `26.40.1` and supports the script's `--validate-app`, `--upload-package`, and `--build-status` commands.

Sources:

- https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/
- https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-pricing-and-availability
- https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price
- https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/
- https://developer.apple.com/app-store/app-privacy-details/

## Prompt-To-Artifact Checklist

| Requirement | Artifact | Current Evidence | Status |
| --- | --- | --- | --- |
| Prepare for App Store Connect | `Docs/AppStoreReadiness.md`, this packet | Preflight, archive/export, screenshots, metadata, privacy notes, and upload helper exist; current IPA local check passes from clean CaptainsLog commit `0485480d8d37fbba5f6e1437a54d3bc0d50c1733` and clean Kit941 commit `9330d58ca0e14d8133250a9051599fecafea03b2` | Locally ready |
| Clean up UI | Fixture screenshot routes and latest PNG audit | Dashboard, Work Map, journal, repositories, AI settings, and Privacy & Data screenshots generated for iPhone and iPad; iPad dashboard uses the adaptive tablet layout with a selected-day journal preview; Work Map, AI provider, and Privacy & Data iPad screens now use wider/two-column layouts; no dashboard sync bar, repository toggle clipping, or oversized Work Map empty space was visible in the checked PNGs | Locally reviewed |
| Make design feel coherent | `.impeccable.md`, fixture screenshots, `Docs/AppStoreDesignReview.md` | Current direction is quiet, precise, journal-like, Apple-native, with Work Map carrying identity; design review scores the current screenshot set 33/40 and recommends no major new features before first TestFlight/App Store Connect pass | Locally reviewed |
| Metadata ready to paste | `Docs/AppStoreMetadata.md` | Name, subtitle, description, keywords, review notes, URLs, screenshot order, privacy draft | Locally ready, legal review open |
| Privacy policy/support ready | `Docs/PrivacyPolicyDraft.md`, `Docs/SupportPageDraft.md`, `Docs/AppStorePrivacyAnswers.md` | URLs passed preflight reachability checks; privacy answers map App Store Connect fields to current code evidence | Locally ready, legal review open |
| Binary export ready | `Scripts/export_app_store_ipa.sh` | Current export produced an IPA with bundle ID `com.blakecrosley.captainslog`, version `1.0.0 (1)`, privacy manifest present, `get-task-allow=false`, encryption flag `false`, and a sibling export manifest with the exact git commit | Locally ready |
| Upload path ready | `Scripts/upload_app_store_ipa.sh` | Local IPA check passes, requires a clean-tree export manifest by default, rejects release builds containing debug screenshot/auth fixture strings, and validate/upload/status require App Store Connect credentials; current validate attempt is blocked by missing API key and issuer env vars | Script ready, external credentials open |
| Screenshots ready | `Scripts/capture_app_store_screenshots.sh`, `Scripts/package_app_store_screenshots.sh` | 12 PNGs generated and packaged for 6.9-inch iPhone and 13-inch iPad upload folders | Locally ready, human marketing acceptance open |
| Physical device smoke | `xcodebuild`, `xcrun devicectl` | A Debug build installed on the connected iPhone 17 Pro Max running iOS 26.4.2 and launched successfully with bundle ID `com.blakecrosley.captainslog`; the latest post-polish device UI-test rerun was blocked by the locked phone | Build/install/launch previously verified; fresh post-polish device UI test open |
| Reviewer/demo path | `CaptainsLogUITests` | UI tests verify first-run Sign in with GitHub and Use Demo Data actions remain readable, then launch fixture data and navigate Settings, Privacy & Data, and selected-day journal detail | Post-polish simulator UI tests passed; earlier device UI tests passed |
| Real data confidence | `Scripts/audit_device_store.sh`, connected iPhone app container | Device-store audit copied the real app database from Blake's iPhone 17 Pro Max and verified aggregate coverage: 104 selected repositories, 12,468 commits, 100% diff-stat coverage in the local store, and no empty days in 2026 through May 17 | Device store verified; final human tap-through/API parity open |

## Local Commands Before Upload

Run these from the repo root:

```sh
Scripts/app_store_readiness_status.sh
Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit
Scripts/upload_app_store_ipa.sh local-check "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```

`Scripts/app_store_readiness_status.sh` is the fastest current-state gate. It checks the local IPA, screenshots, screenshot review contact sheet and review page, clean source state, preflight, and release local check, then lists external blockers such as missing App Store Connect credentials, manual App Store Connect fields, TestFlight processing, legal review, and final human screenshot acceptance.

For a real-account data sanity check on the connected iPhone:

```sh
Scripts/audit_device_store.sh /tmp/captainslog-device-store-script-audit
```

This copies only the app's local data container to the requested temp folder and reports aggregate counts, date coverage, and diff-stat coverage. Do not paste raw commit messages, file paths, or repository names into App Review notes.

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
Scripts/make_app_store_screenshot_contact_sheet.sh /tmp/captainslog-key-state-packaged /tmp/captainslog-appstore-review
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

Before submitting for review, also fill the non-copy manual choices from `Docs/AppStoreMetadata.md`:

- Pricing: free.
- Availability: all countries or regions unless legal review narrows distribution.
- Distribution: public App Store.
- Version release: manual release.
- Age rating: complete the questionnaire from the final binary using `Docs/AppStoreMetadata.md` as the conservative draft.
- Made for Kids: no.
- License agreement: Apple Standard EULA unless legal review provides a custom EULA.
- Content Rights: confirm the final legal/product answer because the app displays user-authorized GitHub repository content.
- App Review contact: enter a real private contact in App Store Connect only.
- Demo account: preferably create a safe GitHub review account with demo repositories and enter those credentials only in App Store Connect.

## Build Upload

Set App Store Connect API credentials in the shell, keeping the `.p8` private key outside the repo:

```sh
export APP_STORE_CONNECT_API_KEY="..."
export APP_STORE_CONNECT_API_ISSUER="..."
export APP_STORE_CONNECT_P8_FILE="/absolute/path/to/AuthKey_....p8"
```

`Scripts/app_store_readiness_status.sh` validates that the API key looks like a 10-character key ID, the issuer looks like a UUID, and the `.p8` file is readable, outside the repo, and has a private-key header. It does not print private-key contents.

Then validate, upload, and check processing:

```sh
Scripts/upload_app_store_ipa.sh app-record "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
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

Do a human pass before submission. The local checks verify size and obvious UI regressions, not marketing quality. Use `Scripts/make_app_store_screenshot_contact_sheet.sh /tmp/captainslog-key-state-packaged /tmp/captainslog-appstore-review` to generate `/tmp/captainslog-appstore-review/review.html` and `/tmp/captainslog-appstore-review/contact-sheet.png` for a fast side-by-side review of both device families.

Use this acceptance bar for the final screenshot marketing decision:

- The first screenshot makes Captain's Log understandable in under five seconds.
- The set reads as one progression: overview, long-range Work Map, daily journal evidence, repository access, optional AI keys, and privacy controls.
- The Work Map/histogram is visible as the product's identity surface, not buried as a secondary settings view.
- Journal screenshots show the daily note and the commit evidence that backs it.
- Repository and Privacy & Data screenshots make GitHub permissions and data handling understandable.
- No screenshot shows real private repository names, live tokens, personal email addresses, debug labels, fixture warnings, simulator chrome, clipped controls, or active sync progress.
- The visual tone stays quiet, precise, and journal-like instead of becoming a generic analytics dashboard.

`Docs/AppStoreDesignReview.md` records the current design verdict and the specific human checks still needed before upload.

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

Use this table as the final owner checklist. A gate is closed only when the evidence column exists, not just when the action was attempted.

| Gate | Action | Evidence that closes it |
| --- | --- | --- |
| App Store Connect app record | Create or confirm the iOS app record with bundle ID `com.blakecrosley.captainslog`, SKU `captainslog-ios`, primary language English (U.S.), and team `M4WTLM6RAQ`. | `Scripts/upload_app_store_ipa.sh app-record "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"` lists the app by bundle ID, and the Apple ID is captured as `APP_STORE_CONNECT_APPLE_ID` for status checks. |
| Manual App Store Connect fields | Enter pricing, availability, distribution, version-release option, age-rating questionnaire, content-rights answer, license choice, Made for Kids answer, App Review contact, and demo-account details using `Docs/AppStoreMetadata.md`. | App Store Connect shows the app version ready to add for review with no missing metadata warnings, and private contact/demo credentials exist only in App Store Connect. |
| App Store Connect API credentials | Create or select an App Store Connect API key with upload permission, then set `APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_API_ISSUER`, and `APP_STORE_CONNECT_P8_FILE`. Keep the `.p8` outside the repo. | `Scripts/app_store_readiness_status.sh` shows API key/issuer and `.p8` as set; `Scripts/upload_app_store_ipa.sh validate "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"` passes. |
| Build upload | Run `Scripts/upload_app_store_ipa.sh upload "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"` after validate passes. | Upload command succeeds and returns either a delivery ID or a build visible in App Store Connect. |
| TestFlight processing | Run `Scripts/upload_app_store_ipa.sh status "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"` with either `APP_STORE_CONNECT_DELIVERY_ID` or `APP_STORE_CONNECT_APPLE_ID`. | Build status is processed/available in App Store Connect or TestFlight, with version `1.0.0` build `1`. |
| Screenshot marketing approval | Open `/tmp/captainslog-appstore-review/contact-sheet.png` and check it against `/tmp/captainslog-appstore-review/README.md`. | Human approval that both device families are legible, private-data safe, quiet/journal-like, and free of debug UI, clipped controls, simulator chrome, and active sync progress. |
| Legal/privacy review | Review the published Privacy Policy, Support page, App Store privacy answers, and optional AI provider disclosures. | Legal/product approval to submit the current privacy answers and published policy URLs, or specific edits applied and rechecked by preflight. |
| Final real-account tap-through | On the real large-account install, open dashboard, Work Map, journal detail, repositories, AI providers, Privacy & Data, and run or observe sync without UI lockup. | Human tap-through confirms reviewer-visible UX quality and data plausibility. The device-store aggregate audit is supporting evidence only; it does not prove GitHub API parity or UX quality by itself. |
