# Captain's Log App Store Metadata

Draft for English (U.S.) App Store Connect fields. This is paste-ready except for legal review of the privacy copy and the final review-test account decision.

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
- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

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

Verified live on May 17, 2026. Before submission, use the published copy or a legally reviewed replacement.

Support URL:

```text
https://blakecrosley.com/captains-log/support
```

Verified live on May 17, 2026 with a real support contact path.

Copyright:

```text
2026 Blake Crosley
```

Age rating notes:

```text
No mature content, social posting, user-to-user communication, commerce, gambling, medical content, location use, or unrestricted web browsing is present in the app code today. Complete the App Store Connect questionnaire from the final binary before submission.
```

Export compliance note:

```text
This build declares ITSAppUsesNonExemptEncryption=false. The app uses Apple system networking/TLS for GitHub and optional AI provider API calls, and does not include custom cryptography. Reconfirm this answer if custom encryption or security functionality is added later.
```

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

Run `Scripts/capture_app_store_screenshots.sh` for repeatable iPhone and iPad captures from the neutral fixture state, then verify and package them with:

```sh
Scripts/app_store_preflight.sh <screenshot-dir>
Scripts/package_app_store_screenshots.sh <screenshot-dir>
```

1. Dashboard with account header, week strip, primary metric, and work map.
2. Work map detail showing a selected month or year.
3. Journal detail with TL;DR and commit evidence.
4. Repository access screen with selected repositories and search.
5. AI provider settings with optional key state.
6. Privacy & Data screen.

Latest audit: on May 17, 2026, the script generated 12 PNGs in `/tmp/captainslog-repo-search-audit`: six iPhone 17 Pro Max screenshots at `1320x2868` and six iPad Pro 13 screenshots at `2064x2752`. The checked screenshots did not show the previous-app breadcrumb, the repository access screen did not clip toggles, and `Scripts/app_store_preflight.sh /tmp/captainslog-repo-search-audit` passed.

Packaged upload folders should contain six ordered images for each family:

- `iphone-6.9/01-dashboard.png` through `06-privacy-data.png`.
- `ipad-13/01-dashboard.png` through `06-privacy-data.png`.

Avoid screenshots that show real private repository names unless the repository is intentionally public and safe to market.

## Privacy Questionnaire Draft

This is a conservative working draft, not a final legal answer.

Data types likely involved for App Functionality:

- User ID: GitHub login/account identifier when signed in.
- Other User Content: repository names, commit messages, commit metadata, changed files, diff stats, and generated journal text.

Likely properties:

- Linked to the user: yes, when tied to the GitHub account or selected repositories.
- Used for tracking: no.
- Used for third-party advertising: no.
- Used for analytics: no in the app code today.
- Shared with third-party AI: only when the user attaches a cloud AI key and generates a journal entry.

Clipboard note: the GitHub sign-in screen copies the short-lived device code to the system pasteboard only when the user taps "Copy & Open GitHub". The app does not read from the pasteboard.

Before submission, confirm whether GitHub API traffic should be represented as App Store "collection" or as user-initiated service traffic under Apple's collection definition. If uncertain, use the conservative disclosure above.
