# Captain's Log App Store Marketing Packet

Prepared for the first English (U.S.) App Store Connect entry. This packet is focused on metadata and marketing copy, not screenshot generation. Use it with `Docs/AppStoreMetadata.md` for the complete field list, `Docs/AppStorePrivacyAnswers.md` for the privacy questionnaire, and `Docs/AppStoreConnectRunbook.md` for the account/signing sequence.

## Current Status

As of the May 19, 2026 no-media refresh, the metadata itself is locally ready: `CAPTAINS_LOG_SKIP_MEDIA_CHECKS=1 Scripts/app_store_readiness_status.sh` passed the App Store field limits, published Support URL, published Privacy Policy URL, privacy manifest, export-compliance flag, icon checks, and current iPhone/iPad build settings.

No new screenshot work was done for this packet refresh. The readiness gate recognized the existing no-screenshot Vision, Watch, and TV simulator launch smokes, which recorded `simctl launch` process IDs. Those checks prove local compile/package/launch viability only and do not change the first-release marketing claim.

The release is not store-ready yet. The current blockers are account, signing, upload, and human review gates, not more marketing copy:

- App Store Connect app record: missing or not visible for `com.blakecrosley.captainslog` by exact bundle relationship, expected SKU `captainslog-ios`, or expected name `Captain's Log`.
- Current IPA/export manifest: missing at `/tmp/captainslog-current-appstore-export/Export/`.
- iOS signing: remote distribution certificates are visible, but the required `IOS_APP_STORE` profile is missing; the visible iOS App Store profile is invalid.
- Native Mac signing: Mac App Store installer certificate and active `MAC_APP_STORE` profile are missing.
- Apple Watch account state: Watch companion bundle ID `com.blakecrosley.captainslog.watchkitapp` is missing or not visible.
- Apple TV signing: shared bundle ID exists, but active `TVOS_APP_STORE` profile is missing.
- Linked package custody: `../941Kit` is clean but ahead of `origin/main` by 1 commit at `fe4bfd3 Add Kit941 localization catalog entries`, so a final export must either push that package save point or explicitly accept the unpushed linked package state.
- Final gates: TestFlight processing, legal/privacy review, App Review contact/demo-account entry, and final real-account tap-through remain open.

## App Store Connect Entry Order

Paste or enter these fields first after the App Store Connect app record exists:

1. App information from `Docs/AppStoreMetadata.md`: name, subtitle, categories, SKU, bundle ID, copyright, Support URL, and Privacy Policy URL.
2. Version information below: promotional text, description, keywords, and App Review notes.
3. Privacy questionnaire from `Docs/AppStorePrivacyAnswers.md`.
4. Manual store choices below: free pricing, public distribution, manual release, not Made for Kids, Apple Standard EULA, compatible Apple Vision Pro availability after signed iOS upload and final acceptance, and Apple Silicon Mac opt-out unless Mac/TestFlight/QA are complete.

Do not paste private App Review contact details, demo-account credentials, trader contact details, Apple IDs, API keys, issuer IDs, or `.p8` private-key paths into repository files. Enter those only in App Store Connect or private local shell state.

## Positioning

Primary positioning:

```text
Captain's Log is a private GitHub work journal for developers who want to remember the work behind their commits.
```

Do say:

- Private GitHub work journal.
- Selected repositories.
- Work Map, changed lines, commits, daily journal notes.
- Local-first storage, Keychain for GitHub and optional AI keys.
- Optional bring-your-own-key OpenAI and Anthropic support.
- Apple Foundation Models when available.

Do not say yet:

- Native visionOS.
- Mac, Apple Watch, or Apple TV availability as shipped product.
- Team analytics, employee monitoring, productivity scoring, or performance management.
- Full privacy/security certification.
- Accessibility Nutrition Label support until each claimed device family is evaluated.

## App Store Connect Metadata

Name:

```text
Captain's Log
```

Subtitle:

```text
GitHub work journal
```

Promotional text:

```text
Turn selected GitHub repositories into a calm daily work journal with commits, diff stats, and private AI summaries.
```

Description:

```text
Captain's Log turns selected GitHub repositories into a private work journal.

Connect GitHub, choose the repositories you care about, and see your work as a readable timeline instead of a wall of commits. Work Map shows commit volume and changed lines across days, weeks, months, and years, while journal entries turn the evidence into notes you can actually remember.

Use Captain's Log to answer practical questions:

- What did I ship today?
- Which repositories took most of my week?
- Was this a small cleanup day or a heavy diff day?
- What should I remember from the actual commits?

Captain's Log is built for memory, not surveillance. It focuses on the repositories you select, keeps GitHub tokens and optional AI provider keys in Keychain, and explains its data flow in the app.

Features:

- GitHub Device Flow sign-in
- Repository selection through GitHub App access
- Daily, weekly, monthly, and yearly work views
- Work Map for commits and changed lines
- Diff stats, changed files, language, and work-type breakdowns
- Daily journal summaries backed by commit evidence
- Apple on-device summaries when available
- Optional bring-your-own-key OpenAI and Anthropic support
- In-app Privacy & Data explanation

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

App Review notes:

```text
Captain's Log is a client for the user's GitHub repository history. GitHub sign-in is required so the user can access repository content from the specific third-party service they selected. The app does not create a separate Captain's Log account.

The app uses GitHub Device Flow. After sign-in, users choose repositories through their GitHub App installation and can sync commits, diff stats, and repository metadata for the selected repositories.

If App Review does not want to connect a GitHub account, the first-run screen includes "Use Demo Data" so the reviewer can inspect the dashboard, Work Map, settings, privacy screen, and journal detail without external credentials.

AI journal generation works on-device with Apple Foundation Models when available. OpenAI and Anthropic are optional bring-your-own-key settings. When a cloud key is attached, the app sends selected commit evidence directly to the selected provider only when the user generates a journal entry.

Background processing indexes older Git history in batches. The app remains usable while indexing continues.
```

## Product Page Copy

Hero headline:

```text
Remember the work behind the commits.
```

Hero subhead:

```text
Captain's Log turns selected GitHub repositories into a private daily journal with Work Map activity, diff stats, and evidence-backed summaries.
```

Short description:

```text
A private GitHub work journal for developers who want to understand what changed, where the time went, and what to remember from the actual commits.
```

Feature blocks:

```text
Work Map
See your GitHub activity by day, week, month, or year using commits or changed lines.

Journal From Evidence
Turn the day's commits and diff stats into a readable note you can revisit later.

Repository Control
Choose the repositories Captain's Log can read through your GitHub App installation.

Private By Design
GitHub tokens and optional AI provider keys stay in Keychain. Cloud AI calls happen only when you attach a key and generate a journal entry.

Demo-Friendly
Use demo data to inspect the dashboard, Work Map, settings, privacy screen, and journal detail without connecting GitHub.
```

Launch announcement:

```text
Captain's Log is a private work journal for GitHub. Connect the repositories you care about, scan your Work Map, and turn commits into daily notes backed by real diff evidence.
```

Social copy:

```text
Captain's Log turns GitHub history into a private work journal: selected repos, Work Map activity, diff stats, and daily notes from the commits you actually made.
```

## Platform Marketing Guidance

First-release public copy should market Captain's Log as an iPhone and iPad app. The iOS target supports iPad through target family `1,2`, and the compatible Apple Vision Pro path is appropriate as App Store Connect availability after signed iOS upload and final acceptance.

Do not market native Mac, Apple Watch, or Apple TV as available until each platform has signed export, TestFlight processing, provisioning validation, and device-appropriate QA. Current local targets are useful progress, but they are not public availability.

Recommended platform language:

```text
Available for iPhone and iPad. Apple Vision Pro availability uses the compatible iPhone/iPad app path.
```

Hold this copy until the native platform gates close:

```text
Native Mac, Apple Watch, and Apple TV companions are planned, but not part of the first public availability claim.
```

## Website FAQ

```text
Do I need a GitHub account?
Yes. Captain's Log reads repository and commit history from GitHub repositories you choose to make available to the app.

Can I try it without connecting GitHub?
Yes. Use Demo Data lets you preview the dashboard, Work Map, settings, privacy screen, and journal detail without external credentials.

What leaves my device?
Captain's Log sends requests to GitHub when you sign in, choose repositories, sync commits, or import diff stats. Journal summaries use Apple on-device models when available. If you attach an OpenAI or Anthropic key, selected commit evidence is sent directly to that provider only when you generate a journal entry.

Where are tokens and keys stored?
GitHub sessions and optional AI provider keys are stored in the device Keychain.

Is this for team monitoring?
No. Captain's Log is a personal developer journal for understanding and remembering your own work.

Does it support Mac, Apple Watch, Apple TV, or Apple Vision Pro?
The first release path is iPhone and iPad, with Apple Vision Pro through the compatible iPhone/iPad app availability path. Native Mac, Apple Watch, and Apple TV companion work should not be marketed as available until signed export, TestFlight, and platform QA are complete.
```

## Manual Store Choices

Use these for App Store Connect unless legal/product review changes them:

| Area | First value |
| --- | --- |
| Primary category | Developer Tools |
| Secondary category | Productivity |
| Pricing | Free |
| Distribution | Public App Store |
| Version release | Manual release |
| Phased release | Off for 1.0 |
| Made for Kids | No |
| Regulated medical device | No / not applicable |
| License | Apple Standard EULA |
| Accessibility Nutrition Labels | Do not indicate support until evaluated per device family |
| Apple Vision Pro | Available as compatible iPhone/iPad app after signed iOS upload and final acceptance |
| Apple Silicon Mac | Opt out unless native Mac signed export, TestFlight, and QA are complete |
| Apple Watch / Apple TV | Do not add public availability claims until signed export, TestFlight, provisioning validation, and QA are complete |

## Official Apple Cross-Check

- Apple says an App Store Connect app record must be created before uploading a build, and multi-platform single-purchase apps can be created as one record with shared bundle ID and platform-specific information: https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- Apple's platform version reference sets promotional text, description, keyword, support URL, and screenshot requirements and limits: https://developer.apple.com/help/app-store-connect/reference/platform-version-information/
- Apple's product page guidance says the first sentence matters, promotional text can be updated without a new app version, and descriptions should focus on unique features rather than unnecessary keyword stuffing: https://developer.apple.com/app-store/product-page/
- Apple says iPhone and iPad apps are available on Apple Vision Pro unless availability is edited in App Store Connect: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-apple-vision-pro
- Apple says App Privacy details are required for new apps and updates and must include app and integrated third-party data practices: https://developer.apple.com/app-store/app-privacy-details/
- Apple says Accessibility Nutrition Labels are voluntary to start, appear on product pages, and should be indicated only after evaluating the app's supported features: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/
