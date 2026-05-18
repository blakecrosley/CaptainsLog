# Captain's Log App Store Connect Runbook

Use this during the first App Store Connect/TestFlight session. It is the short operator path; keep `Docs/AppStoreConnectSubmission.md` open for evidence, `Docs/AppStoreCompletionAudit.md` open for gate status, and `Docs/AppStoreMetadata.md` open for paste-ready copy.

## Start Here

From the repo root:

```sh
Scripts/app_store_readiness_status.sh
```

Use the summary as the gate. If it only reports the known missing/stale IPA state, make one export-signing path available, then regenerate the IPA before continuing into App Store Connect. The two supported paths are a local Apple Distribution/iOS Distribution identity for team `M4WTLM6RAQ`, or App Store Connect API-key env vars for `xcodebuild` provisioning updates. After the current IPA passes local checks, the expected remaining blockers before submission are external: credentials, app record, manual fields, upload/TestFlight processing, screenshot approval, legal/privacy review, and final real-account tap-through.

Do not commit private App Store Connect contact details, demo-account credentials, trader contact details, Apple IDs, API keys, issuer IDs, or `.p8` private keys.

If readiness reports a missing or stale IPA, make either Xcode distribution signing or `xcodebuild` API-key provisioning auth available, then run:

```sh
Scripts/app_store_signing_status.sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
```

The signing status script checks the local Xcode/App Store upload toolchain and whether an Apple Distribution/iOS Distribution identity is available for team `M4WTLM6RAQ`. A `Developer ID Application` identity is for macOS distribution and does not satisfy the iOS App Store IPA export gate.

The export script checks for Xcode 26 or later, an iOS 26 or newer SDK, and an Apple Distribution/iOS Distribution signing identity for team `M4WTLM6RAQ` before archiving. If `APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_API_ISSUER`, and `APP_STORE_CONNECT_P8_FILE` are all set, it passes those credentials to `xcodebuild` so automatic signing can authenticate with App Store Connect for provisioning updates. It then stages archive/export output and replaces the current IPA folder only after export validation succeeds.

If signing status still reports a missing distribution identity, either configure the App Store Connect API-key environment variables from `Docs/AppStoreConnectEnv.template.sh` before export, or open Xcode > Settings > Accounts, sign into an Apple ID that belongs to team `M4WTLM6RAQ`, select the team, open Manage Certificates, then use `+` > Apple Distribution. If profiles still look stale afterward, use Download Manual Profiles and rerun `Scripts/app_store_signing_status.sh`.

## 1. Create Or Confirm The App Record

In App Store Connect, create or confirm:

- Platform: iOS
- Name: `Captain's Log`
- Primary language: English (U.S.)
- Bundle ID: `com.blakecrosley.captainslog`
- SKU: `captainslog-ios`
- Team: `M4WTLM6RAQ`

Evidence that closes this step:

```sh
export APP_STORE_CONNECT_PROVIDER_PUBLIC_ID="..."
Scripts/upload_app_store_ipa.sh app-record
```

Run the evidence command after API credentials are configured in step 4 and `APP_STORE_CONNECT_PROVIDER_PUBLIC_ID` is set. If App Store Connect gives an Apple ID for this app, keep it locally as `APP_STORE_CONNECT_APPLE_ID` for status checks. Do not commit it unless you intentionally decide it is safe to document.

## 2. Enter Product Metadata

Use `Docs/AppStoreMetadata.md`.

Enter the paste-ready fields:

- Name, subtitle, category, SKU, bundle ID.
- Privacy Policy URL and Support URL.
- Promotional text, description, keywords.
- App Review notes.

Make the manual choices from the table in `Docs/AppStoreMetadata.md`:

- Price: free.
- Availability: broad unless legal narrows it.
- Apple Vision Pro availability: make available as the compatible iPhone/iPad app after final smoke-test acceptance; do not claim native visionOS.
- Apple Silicon Mac availability: opt out unless you complete a Mac/TestFlight pass and intentionally accept that extra platform.
- Distribution: public App Store.
- Version release: manual.
- Made for Kids: no.
- License: Apple Standard EULA unless legal supplies a custom one.
- Regulated medical device: no / not applicable for the current binary.
- Tax category: App Store software unless tax/legal changes it.
- Accessibility Nutrition Labels: optional for this first release unless App Store Connect requires entry.

Resolve these only inside App Store Connect:

- App Review contact.
- Demo GitHub review account credentials, if used.
- EU DSA trader status and any trader contact details.
- Region-specific availability/compliance prompts.
- Apple Vision Pro availability if App Store Connect shows it: keep or select "Make this app available on Apple Vision Pro" for the compatible iPhone/iPad app.
- Apple Silicon Mac availability if App Store Connect shows it: deselect "Make this app available" for the first release unless a Mac/TestFlight pass is completed.
- Labels and Markings URLs, only if legal/product supplies one.
- Content Rights final answer.
- Age-rating questionnaire from the final binary.

Platform availability notes for the first App Review submission:

- iPhone and iPad: submit as the current universal iOS app.
- Apple Vision Pro: make available as the compatible iPhone/iPad app after `Scripts/smoke_vision_compatible_launch.sh /tmp/captainslog-vision-smoke` still reaches the first-run UI. Do not add native visionOS screenshots or metadata unless a separate visionOS target exists.
- Mac: do not enable the iPhone/iPad app on Apple Silicon Mac for the first release, and do not submit the native macOS target until `Scripts/smoke_macos_launch.sh /tmp/captainslog-macos-smoke`, Mac signing/export, screenshots, TestFlight, and human QA are complete.
- Apple Watch and Apple TV: no action in App Store Connect for this release because there is no watchOS or tvOS app target.

Evidence that closes this step: App Store Connect shows the version ready to add for review with no missing-metadata warnings, and private details remain only in App Store Connect.

## 3. Enter App Privacy

Use `Docs/AppStorePrivacyAnswers.md`.

Current conservative answers:

- Data Used to Track You: no.
- Data Linked to You for App Functionality: GitHub profile name when returned, GitHub login/account identifier, repository names, commit messages, commit metadata, changed file paths, diff stats, generated journal text, and work classifications.
- Data Not Linked to You: none for this build unless App Store Connect requires Apple-provided diagnostics separately.
- Optional OpenAI/Anthropic processing is bring-your-own-key and only used when the user attaches a provider key and generates output.

Evidence that closes this step: legal/product approves the submitted privacy answers and published policy URLs, or specific edits are applied and `Scripts/app_store_readiness_status.sh` still passes.

## 4. Configure Upload Credentials

Confirm App Store Connect API access exists first. Apple requires the Account Holder to request API access before keys can be used.

For this upload helper, create or choose a team API key with upload permission. The helper uses `altool`'s API key plus issuer ID authentication path, so a team key is the clearest supported route for the first submission.

Set API credentials in the shell only:

```sh
export APP_STORE_CONNECT_API_KEY="..."
export APP_STORE_CONNECT_API_ISSUER="..."
export APP_STORE_CONNECT_P8_FILE="/absolute/path/to/AuthKey_....p8"
```

`Docs/AppStoreConnectEnv.template.sh` contains a safe placeholder-only shell template for these exports plus provider/status variables. Do not enter real credentials in the tracked file; copy the placeholder exports into a private shell session or a gitignored local file outside this repo.

If `Scripts/app_store_signing_status.sh` reports that candidate `.p8` private-key files are already staged, choose the matching App Store Connect key ID in Apple, then point `APP_STORE_CONNECT_P8_FILE` at the staged path for that key. The current machine has multiple staged candidates, so do not rely on implicit key search for the first submission:

Apple shows team key IDs in App Store Connect under Users and Access > Integrations, in the Active keys table. The issuer UUID appears near the top of that same Integrations page.

```sh
export APP_STORE_CONNECT_API_KEY="<KEY_ID>"
export APP_STORE_CONNECT_API_ISSUER="<ISSUER_UUID>"
export APP_STORE_CONNECT_P8_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8"
```

The readiness, export, and upload scripts fail early if the selected file name does not match `AuthKey_<KEY_ID>.p8`. Only set `CAPTAINS_LOG_ALLOW_MISMATCHED_P8_FILENAME=1` after manually verifying the selected file belongs to the key ID.

Keep the `.p8` outside this repo and outside any other git working tree. Preferred location:

```text
~/.appstoreconnect/private_keys/AuthKey_<key>.p8
```

Create that folder with owner-only permissions, then move the downloaded key into it:

```sh
mkdir -p "$HOME/.appstoreconnect/private_keys"
chmod 700 "$HOME/.appstoreconnect" "$HOME/.appstoreconnect/private_keys"
mv "/path/to/downloaded/AuthKey_<key>.p8" "$HOME/.appstoreconnect/private_keys/"
chmod 600 "$HOME/.appstoreconnect/private_keys/AuthKey_<key>.p8"
```

Verify the local credential guard without contacting Apple:

```sh
Scripts/upload_app_store_ipa.sh credential-guard-self-test
Scripts/app_store_readiness_status.sh
```

The export script uses the same API key, issuer, and `.p8` env vars for `xcodebuild` provisioning updates, so the same private-key custody rules apply: keep the `.p8` outside this repo and outside any git working tree.

Then set `APP_STORE_CONNECT_PROVIDER_PUBLIC_ID` for the team that owns `com.blakecrosley.captainslog`. Xcode 26.5 `altool --list-providers` does not support API-key authentication, so obtain this value from App Store Connect, Transporter, or a manually authenticated altool session, then rerun `Scripts/app_store_readiness_status.sh`. Evidence that closes this step: readiness shows API key/issuer, provider public ID, and `.p8` as valid, and no App Store private key material exists inside this repo or another git working tree.

## 5. Validate, Upload, And Check Processing

After `Scripts/app_store_readiness_status.sh` passes and the current IPA exists, validate and upload it:

```sh
Scripts/upload_app_store_ipa.sh validate "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
Scripts/upload_app_store_ipa.sh upload "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```

After upload, check status using either a delivery ID or the app Apple ID:

```sh
export APP_STORE_CONNECT_DELIVERY_ID="..."
Scripts/upload_app_store_ipa.sh status "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```

or:

```sh
export APP_STORE_CONNECT_APPLE_ID="..."
Scripts/upload_app_store_ipa.sh status "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```

Evidence that closes this step: upload succeeds and build `1.0.0 (1)` is processed/available in App Store Connect or TestFlight.

## 6. Upload Screenshots

If the screenshot set needs to be regenerated, run the capture, preflight, package, contact-sheet, and screenshot text-audit commands from `Docs/AppStoreConnectSubmission.md`. The package and review scripts stage output first, then replace the current upload/review folders only after generation succeeds, so a failed regeneration should leave the last reviewed screenshots intact.

Use the packaged folders:

- `/tmp/captainslog-key-state-packaged/iphone-6.9`
- `/tmp/captainslog-key-state-packaged/ipad-13`

Upload in this order for each family:

1. `01-dashboard.png`
2. `02-work-map.png`
3. `03-journal.png`
4. `04-repositories.png`
5. `05-ai-providers.png`
6. `06-privacy-data.png`

Before upload, open:

```sh
Scripts/open_app_store_screenshot_review.sh
```

or inspect the artifacts directly:

```text
/tmp/captainslog-appstore-review/contact-sheet.png
/tmp/captainslog-appstore-review/review.html
```

Evidence that closes this step: human approval that both device families are legible, private-data safe, quiet/journal-like, and free of debug UI, clipped controls, simulator chrome, and active sync progress.

## 7. Final Human Tap-Through

On the real large-account install, check:

- Dashboard.
- Work Map.
- Journal detail.
- Repositories.
- AI providers.
- Privacy & Data.
- Sync behavior without UI lockup.

Supporting command:

```sh
Scripts/audit_device_store.sh /tmp/captainslog-device-store-script-audit
```

Evidence that closes this step: human tap-through confirms reviewer-visible UX quality and data plausibility. The device-store audit is supporting evidence only; it does not prove GitHub API parity or UX quality by itself.

## 8. Before Add For Review

Do this final pass inside App Store Connect after the build finishes processing:

- Select the processed `1.0.0 (1)` build for the app version.
- Confirm App Privacy is complete and matches `Docs/AppStorePrivacyAnswers.md`.
- Confirm pricing, country/region availability, Apple Vision Pro availability, Apple Silicon Mac opt-out, age rating, content rights, release option, license, and any regional/compliance prompts are complete.
- Confirm screenshots are uploaded in the packaged order for both iPhone and iPad.
- Confirm App Review contact, review notes, and any demo GitHub account credentials are present only in App Store Connect.
- Confirm legal/privacy and screenshot marketing approval are complete.

Evidence that closes this step: App Store Connect shows no missing-metadata warnings and allows the version to be added for review.
