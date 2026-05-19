# Captain's Log App Store Metadata

Draft for English (U.S.) App Store Connect fields. This is paste-ready except for legal review of the privacy copy and the final review-test account decision. For the detailed privacy questionnaire entry, use `Docs/AppStorePrivacyAnswers.md`.

## Source Constraints

- App name: 2 to 30 characters.
- Subtitle: 30 characters maximum.
- Promotional text: 170 characters maximum.
- Description: 4000 characters maximum, plain text.
- Keywords: 100 bytes maximum; do not duplicate the app or company name, and do not use other app or company names.
- Support URL: required and must lead to actual contact information.
- Privacy Policy URL: required for iOS and macOS apps.
- App Review notes: 4000 bytes maximum.

Official references:

- App information: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Platform version information: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Set app age rating: https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/
- Age rating values and definitions: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- Pricing and availability: https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/app-pricing-and-availability
- Set app price: https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price
- Version release option: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/
- Apple Vision Pro availability: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-apple-vision-pro
- Apple Silicon Mac availability: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon/
- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Accessibility Nutrition Labels overview: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/
- Manage Accessibility Nutrition Labels: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/manage-accessibility-nutrition-labels/
- EU Digital Services Act trader requirements: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
- Declare regulated medical device status: https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status/
- Set a tax category: https://developer.apple.com/help/app-store-connect/manage-app-information/set-a-tax-category

## App Information

Name:

```text
Captain's Log
```

Subtitle:

```text
GitHub work journal
```

Primary category:

```text
Developer Tools
```

Secondary category:

```text
Productivity
```

SKU:

```text
captainslog-ios
```

Bundle ID:

```text
com.blakecrosley.captainslog
```

Privacy Policy URL:

```text
https://blakecrosley.com/captains-log/privacy
```

Verified by preflight on May 18, 2026. Before submission, use the published copy or a legally reviewed replacement.

Support URL:

```text
https://blakecrosley.com/captains-log/support
```

Verified by preflight on May 18, 2026 with a real support contact path.

Copyright:

```text
2026 Blake Crosley
```

Age rating notes:

```text
No mature content, social posting, user-to-user communication, commerce, gambling, medical content, location use, advertising, or embedded unrestricted web browsing is present in the app code today. The app does display user-authorized GitHub repository content, including repository names, commit messages, file paths, and diffs, so answer any user-generated-content prompt conservatively from the final App Store Connect questionnaire wording.
```

Export compliance note:

```text
This build declares ITSAppUsesNonExemptEncryption=false. The app uses Apple system networking/TLS for GitHub and optional AI provider API calls, and does not include custom cryptography. Reconfirm this answer if custom encryption or security functionality is added later.
```

## Manual App Store Connect Choices

These fields are not all pasteable text fields, but they should be decided before the first App Review submission.

| App Store Connect area | Recommended first submission value | Notes |
| --- | --- | --- |
| Pricing | Free | Captain's Log has no in-app purchases or subscriptions in this build. Revisit if paid features are added. |
| App Availability | All countries or regions where the App Store can distribute the app, unless legal review narrows this | The app has no known region-specific content, commerce, medical, gambling, or location behavior. |
| Apple Vision Pro Availability | Make available as the compatible iPhone/iPad app, pending final smoke-test acceptance | Apple makes iPhone and iPad apps available on Apple Vision Pro by default unless edited in App Store Connect. Current local evidence proves the compatible app builds, installs, launches, and renders its first-run UI on a Vision Pro simulator without the previous raw keychain warning; confirm signed TestFlight/auth behavior before final acceptance. This is not a native visionOS app; keep native visionOS screenshots/metadata out of the first submission unless a separate visionOS target is added later. |
| Apple Silicon Mac Availability | Opt out for the first release unless a Mac/TestFlight pass is completed | Apple can make compatible iPhone and iPad apps available on Apple Silicon Macs through the Mac App Store unless availability is edited. Captain's Log has a native macOS target aligned to the shared App Store bundle ID plus an iOS-on-Mac destination; the native target has automatic signing build settings and local smoke/screenshots, but signed Mac App Store export, TestFlight pass, and human QA acceptance are still open. |
| Apple Watch / Apple TV Availability | No action for the first release unless the platform work is intentionally finished | Captain's Log now has watchOS and tvOS companion targets that build, launch with signing disabled, include platform icon/top-shelf assets, produce local App Store screenshot artifacts, and share an aggregate snapshot through WatchConnectivity plus iCloud key-value sync. Return and Get Bananas remain useful local precedents, not substitute evidence. Watch still needs its Developer Portal companion bundle ID and iCloud capability after explicit account-mutation approval. Apple TV uses the existing shared `com.blakecrosley.captainslog` bundle ID, so its remaining blockers are signed export, TestFlight, provisioning validation, human screenshot acceptance, and living-room QA. |
| Region-specific Availability Prompts | Resolve if App Store Connect shows them, or narrow availability | Apple's required-properties table lists country-specific availability/compliance fields for some regions. If App Store Connect requests extra information for South Korea, China mainland, Vietnam, or another storefront, resolve it in App Store Connect before review or remove that storefront from the first release. |
| EU Digital Services Act Trader Status | Legal/business-owner decision required before EU availability | Apple requires a trader/non-trader declaration. If distributing in the EU as a trader, Apple may display provided address, phone, and email contact information on the App Store product page. Enter any private contact details only in App Store Connect. |
| Labels and Markings URLs | Leave blank unless legal/product has required labeling URLs | Apple lists Labels and Markings URLs as app information. Captain's Log has no regulated physical product labels or markings in the current binary, so only provide a legal-approved URL if App Store Connect asks for one. |
| Regulated Medical Device Status | No / not applicable | Captain's Log is a developer tool, does not use HealthKit, does not access health data, is not in Health & Fitness or Medical, and has no medical or treatment information in the current binary. |
| Tax Category | App Store software | Apple assigns this default if unchanged. Use it unless tax/legal review identifies a more specific category. |
| Distribution Methods | Public App Store distribution | Do not set up private/custom distribution for the first public review unless the release strategy changes. |
| Content Rights | Legal/product decision required; conservative answer is that the app accesses user-authorized GitHub repository content | The app does not ship third-party media, but it displays repository names, commit messages, paths, and diffs obtained from GitHub after user authorization. Confirm the exact App Store Connect answer before submission. |
| Age Rating | Complete the questionnaire from the final binary; expected low-risk developer-tool profile | No mature, medical, gambling, contest, commerce, advertising, location, chat, or embedded browser behavior was found in the current app surface. Treat GitHub repository history as user-supplied content if the questionnaire asks about user-generated content. |
| Accessibility Nutrition Labels | Optional for the first release unless App Store Connect requires it at submission time | Do not publish support claims until common tasks are tested per device. Candidate areas to evaluate later: VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, and Reduced Motion. Captions and Audio Descriptions are not applicable because this build has no video or audio content. |
| Made for Kids | No | The app is a developer tool for GitHub repository history, not a Kids category app. |
| License Agreement | Apple Standard EULA | Use Apple's standard license unless legal review provides a custom EULA. |
| Version Release Option | Manual release | Keeps the first App Store release from going live automatically after approval. TestFlight distribution is separate from App Store release. |
| Phased Release | Off for version 1.0 | Phased release mainly matters for later updates with automatic App Store release. |
| App Review Contact | Enter a real name, email, and phone in App Store Connect only | Do not commit private contact information here. |
| Demo Account | Preferred: create a purpose-built GitHub review account with safe demo repositories and enter credentials only in App Store Connect | The app also has "Use Demo Data" for reviewers who do not want to connect GitHub, but a live review account is safer if App Review wants to test GitHub sync. Never commit demo credentials. |
| App Store Connect Apple ID | Capture after app record creation | Store as `APP_STORE_CONNECT_APPLE_ID` locally for build-status checks; do not commit it unless intentionally documenting a public identifier. |

## Version Information

Promotional text:

```text
Turn selected GitHub repositories into a calm daily work journal with commits, diff stats, and private AI summaries.
```

Description:

```text
Captain's Log turns selected GitHub repositories into a simple work journal.

Connect GitHub, choose the repositories you care about, and see your work as a readable timeline instead of a wall of commits. The dashboard shows recent activity, changed lines, commit volume, and a contribution-style work map so you can understand what changed over time.

Use it to answer practical questions:

- What did I ship today?
- Which repositories took most of my week?
- Was this a small cleanup day or a heavy diff day?
- What should I remember from the actual commits?

Captain's Log is designed to be quiet and local-first. GitHub tokens and optional AI provider keys are stored on device in Keychain. Journal summaries use Apple Foundation Models when available. If you attach your own OpenAI or Anthropic key, the app sends selected commit evidence directly to that provider only when you generate a journal entry.

Features:

- GitHub Device Flow sign-in
- Repository selection for installed GitHub App access
- Daily, weekly, monthly, and yearly work views
- Contribution-style work map for commits and changed lines
- Diff stats, changed files, language, and work-type breakdowns
- Daily journal summaries backed by commit evidence
- Optional bring-your-own-key OpenAI and Anthropic support
- In-app privacy and data explanation

Captain's Log is for developers who want a fast, private way to remember the work behind the commits.
```

Keywords:

```text
git,commits,journal,developer,changelog,repository,history,diff,code,worklog,devlog
```

What's New:

```text
Initial TestFlight build.
```

This field is not available for the first App Store version, but keep this ready for TestFlight notes or later builds.

## App Review Notes

```text
Captain's Log is a client for the user's GitHub repository history. GitHub sign-in is required so the user can access repository content from the specific third-party service they selected. The app does not create a separate Captain's Log account.

The app uses GitHub Device Flow. After sign-in, users choose repositories through their GitHub App installation and can sync commits, diff stats, and repository metadata for the selected repositories.

If App Review does not want to connect a GitHub account, the first-run screen includes "Use Demo Data" so the reviewer can inspect the dashboard, work map, settings, privacy screen, and journal detail without external credentials.

AI journal generation works on-device with Apple Foundation Models when available. OpenAI and Anthropic are optional bring-your-own-key settings. When a cloud key is attached, the app sends selected commit evidence directly to the selected provider only when the user generates a journal entry.

Background processing indexes older Git history in batches. The app remains usable while indexing continues.
```

## Screenshot Set

Run `Scripts/capture_app_store_screenshots.sh` for repeatable iPhone and iPad captures from the neutral fixture state, then verify, package, and generate the human review page/contact sheet with:

```sh
Scripts/app_store_preflight.sh <screenshot-dir>
Scripts/package_app_store_screenshots.sh <screenshot-dir> /tmp/captainslog-key-state-packaged
Scripts/make_app_store_screenshot_contact_sheet.sh /tmp/captainslog-key-state-packaged /tmp/captainslog-appstore-review
Scripts/audit_app_store_screenshot_text.sh /tmp/captainslog-key-state-packaged
```

1. Dashboard with account header, week strip, primary metric, and work map.
2. Work map detail showing a selected month or year.
3. Journal detail with TL;DR and commit evidence.
4. Repository access screen with selected repositories and search.
5. AI provider settings with an attached demo key state.
6. Privacy & Data screen.

Latest audit: on May 18, 2026, the scripts generated 12 PNGs in `/tmp/captainslog-key-state-audit`: six iPhone 17 Pro Max screenshots at `1320x2868` and six iPad Pro 13 portrait screenshots at `2064x2752`. The checked screenshots did not show the previous-app breadcrumb, the repository access screen did not clip toggles, the AI settings screen showed an attached demo key state, `Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit` passed, and `Scripts/audit_app_store_screenshot_text.sh /tmp/captainslog-key-state-packaged` found no rejected App Store text. The screenshot validators also accept Apple's 13-inch iPad landscape size `2752x2064` if a later marketing pass chooses landscape iPad screenshots.

Packaged upload folders should contain six ordered images for each family:

- `iphone-6.9/01-dashboard.png` through `06-privacy-data.png`.
- `ipad-13/01-dashboard.png` through `06-privacy-data.png`.

Latest packaged output: `/tmp/captainslog-key-state-packaged`. Latest human review output: `/tmp/captainslog-appstore-review`.

The packaging and contact-sheet scripts stage their output before replacing the current folders, so a failed regeneration should leave the last reviewed package and contact sheet intact.

Avoid screenshots that show real private repository names unless the repository is intentionally public and safe to market.

## Privacy Questionnaire Draft

Use the paste-ready working draft in `Docs/AppStorePrivacyAnswers.md`.

Conservative summary:

- Data Used to Track You: no.
- Data Linked to You for App Functionality: GitHub profile name when returned, GitHub login/account identifier, GitHub profile/avatar URLs for account display, repository names, commit messages, commit metadata, changed file paths, diff stats, generated journal text, and work classifications.
- Data Not Linked to You: none in this build unless App Store Connect requires Apple-provided diagnostics to be handled separately.
- Optional cloud AI: OpenAI and Anthropic receive selected commit evidence only when the user attaches that provider key and generates AI output.
- Pasteboard: the app writes the short-lived GitHub device code only when the user taps "Copy & Open GitHub"; it does not read the pasteboard.
