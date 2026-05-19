# Captain's Log App Store Privacy Answers

Draft status: paste-ready working draft for App Store Connect. This is conservative product guidance, not legal advice. Use this for the first TestFlight/App Review setup unless legal review provides a narrower answer.

## Basis

Apple's App Privacy Details guidance says App Store Connect answers need to account for data collected by the app or integrated third-party partners, even when the purpose is app functionality. It also distinguishes data collected from the app from data processed only on device. Captain's Log is local-first, but it signs in to GitHub, requests selected GitHub repository history, and can send selected commit evidence to OpenAI or Anthropic when the user attaches a cloud AI key.

Official references:

- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Manage App Privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

## Recommended App Privacy Label

### Data Used To Track You

Answer: No.

Evidence: The privacy manifest sets `NSPrivacyTracking` to `false`, has no tracking domains, and the current code review did not find advertising, third-party tracking, or product analytics SDKs in the app target.

### Data Linked To You

Use: App Functionality.

Do not mark: Third-Party Advertising, Developer Advertising or Marketing, Analytics, Product Personalization, or Other Purposes, unless the product changes before submission.

Recommended disclosed data types:

| App Store Connect category | Data type | Answer | Purpose | Notes |
| --- | --- | --- | --- | --- |
| Contact Info | Name | Conservative: Yes | App Functionality | The GitHub `/user` response can include a profile display name. The app stores it locally for account display. If legal review treats the GitHub profile response as local processing rather than collected data, this may be narrowed. |
| Identifiers | User ID | Yes | App Functionality | GitHub login/account identifier is used to show the active account and associate selected repositories with that account. The app also stores GitHub profile and avatar URLs locally for account display. |
| User Content | Other User Content | Yes | App Functionality | Repository names, commit messages, commit metadata, changed file paths, diff stats, generated journal text, work classifications, and aggregate companion status counts. This is the core content of the app. The Watch/TV companion snapshot intentionally excludes repository names, commit messages, changed file paths, generated journal text, GitHub tokens, and AI provider keys. |

### Data Not Linked To You

Answer: None for this build, unless App Store Connect requires a separate non-linked entry for Apple-provided diagnostics outside the app's control. The app does not include its own crash, performance, product analytics, advertising, or tracking SDK.

### Data Not Collected By Captain's Log Today

Use "No" for these categories in the current binary:

- Location: Precise Location, Coarse Location.
- Contact Info: Email Address, Phone Number, Physical Address, Other User Contact Info.
- Health and Fitness: Health, Fitness.
- Financial Info: Payment Info, Credit Info, Other Financial Info.
- Sensitive Info.
- Contacts.
- User Content: Emails or Text Messages, Photos or Videos, Audio Data, Gameplay Content, Customer Support Data.
- Browsing History.
- Search History.
- Identifiers: Device ID.
- Purchases: Purchase History.
- Usage Data: Product Interaction, Advertising Data, Other Usage Data.
- Diagnostics: Crash Data, Performance Data, Other Diagnostic Data.
- Surroundings, Body, and Other Data Types.

Important caveat: if future builds add analytics, crash reporting, marketing attribution, email capture, account creation, payments, or server sync beyond Apple's iCloud key-value companion snapshot, update the privacy label before upload or release.

## Third-Party Processing Notes

GitHub:

- Required for real repository history.
- Used for Device Flow sign-in, selected repository access, commit history, repository metadata, and diff stats.
- Users can disconnect GitHub in the app and can revoke or change repository access in GitHub.

Apple Foundation Models:

- Used on device when available.
- No cloud AI provider receives commit evidence when the app uses the on-device Apple model.

OpenAI:

- Optional bring-your-own-key setting.
- Used only when the user attaches an OpenAI key and generates journal/classification output.
- The request can include repository names, commit messages, changed file paths, additions, deletions, and related commit evidence.

Anthropic:

- Optional bring-your-own-key setting.
- Used only when the user attaches an Anthropic key and generates journal output.
- The request can include repository names, commit messages, changed file paths, additions, deletions, and related commit evidence.

Pasteboard:

- The app writes the short-lived GitHub device code only when the user taps "Copy & Open GitHub".
- The app does not read the pasteboard.
- This should not be entered as a collected data type, but it is useful to explain if App Review asks about clipboard behavior.

## App Review Sign-In Note

Paste this in App Review Notes if space allows:

```text
Captain's Log is a client for the user's GitHub repository history. GitHub sign-in is required so the user can access repository content from that specific third-party service. The app does not create a separate Captain's Log account. Reviewers can also use the first-run "Use Demo Data" option to inspect the dashboard, Work Map, settings, privacy screen, and journal detail without connecting GitHub.
```

Reasoning: Apple App Review Guideline 4.8 requires an equivalent login option for third-party/social login when that login creates or authenticates the user's primary account with the app. The same guideline says another login service is not required when the app is a client for a specific third-party service and users must sign in to that account to access their content. Captain's Log should clearly explain that GitHub is the content source, not a generic social login.

## Evidence Map

Code evidence checked for this draft:

- GitHub account identity fields: `CaptainsLog/Services/GitHubDTOs.swift`
- GitHub API and OAuth/device endpoints: `CaptainsLog/Services/GitHubAPIClient.swift`
- GitHub account local model: `CaptainsLog/Models/GitRecords.swift`
- Commit and diff local model: `CaptainsLog/Models/GitRecords.swift`
- GitHub token storage in Keychain: `CaptainsLog/Services/KeychainTokenStore.swift`
- AI key storage in Keychain: `CaptainsLog/Services/AIProviderCredentialStore.swift`
- OpenAI journal and classification endpoints: `CaptainsLog/Services/JournalSummarizer.swift`, `CaptainsLog/Services/OpenAIWorkClassifier.swift`
- Anthropic journal endpoint: `CaptainsLog/Services/JournalSummarizer.swift`
- Pasteboard write: `CaptainsLog/Services/ClipboardService.swift`, `CaptainsLog/Views/AuthAndRepoViews.swift`
- In-app Privacy & Data copy: `CaptainsLog/Views/PrivacyDataView.swift`
- Privacy manifest: `CaptainsLog/Resources/PrivacyInfo.xcprivacy`
- Export compliance flag: `CaptainsLog/App/CaptainsLog-iOS-Info.plist`

## Before Final Submission

- Re-run `Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit`.
- Reconfirm no analytics, crash SDK, payment, email capture, server account, or server sync was added after this draft.
- Have the published privacy policy legally reviewed.
- If App Review requires a real account, create a safe GitHub review account with non-private demo repositories instead of using a personal account.
