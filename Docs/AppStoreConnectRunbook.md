# Captain's Log App Store Connect Runbook

Use this during the first App Store Connect/TestFlight session. It is the short operator path; keep `Docs/AppStoreConnectSubmission.md` open for evidence, `Docs/AppStoreCompletionAudit.md` open for gate status, and `Docs/AppStoreMetadata.md` open for paste-ready copy.

## Start Here

From the repo root:

```sh
Scripts/app_store_readiness_status.sh
```

Proceed only if the summary says local readiness passed. The expected remaining blockers before App Store Connect work are external: credentials, app record, manual fields, upload/TestFlight processing, screenshot approval, legal/privacy review, and final real-account tap-through.

Do not commit private App Store Connect contact details, demo-account credentials, trader contact details, Apple IDs, API keys, issuer IDs, or `.p8` private keys.

If readiness reports a missing or stale IPA, make App Store distribution signing available in Xcode, then run:

```sh
Scripts/app_store_signing_status.sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
```

The export script checks for an Apple Distribution/iOS Distribution signing identity before archiving. It then stages archive/export output and replaces the current IPA folder only after export validation succeeds.

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
Scripts/upload_app_store_ipa.sh app-record
```

If App Store Connect gives an Apple ID for this app, keep it locally as `APP_STORE_CONNECT_APPLE_ID` for status checks. Do not commit it unless you intentionally decide it is safe to document.

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
- Labels and Markings URLs, only if legal/product supplies one.
- Content Rights final answer.
- Age-rating questionnaire from the final binary.

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

Create or choose an App Store Connect API key with upload permission.

Set credentials in the shell only:

```sh
export APP_STORE_CONNECT_API_KEY="..."
export APP_STORE_CONNECT_API_ISSUER="..."
export APP_STORE_CONNECT_P8_FILE="/absolute/path/to/AuthKey_....p8"
```

Keep the `.p8` outside this repo. Preferred location:

```text
~/.appstoreconnect/private_keys/AuthKey_<key>.p8
```

Verify the local credential guard without contacting Apple:

```sh
Scripts/upload_app_store_ipa.sh credential-guard-self-test
Scripts/app_store_readiness_status.sh
```

Evidence that closes this step: readiness shows API key/issuer and `.p8` as valid, and no App Store private key material exists inside the repo.

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
