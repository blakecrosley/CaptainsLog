# Captain's Log App Store Connect Runbook

Use this during the first App Store Connect/TestFlight session. It is the short operator path; keep `Docs/AppStoreConnectSubmission.md` open for evidence, `Docs/AppStoreCompletionAudit.md` open for gate status, and `Docs/AppStoreMetadata.md` open for paste-ready copy.

## Start Here

From the repo root:

```sh
Scripts/app_store_readiness_status.sh
```

Use the summary as the gate. If it reports Kit941 upstream drift, push the clean Kit941 commits or explicitly accept the unpushed local package state before final export because Captain's Log links `../941Kit` directly and the export manifest records that package commit. If readiness only reports the known missing/stale IPA state after source custody is settled, make one export-signing path complete, then regenerate the IPA before continuing into App Store Connect. The two supported paths are a local Apple Distribution/iOS Distribution identity for team `M4WTLM6RAQ`, or App Store Connect API-key env vars for `xcodebuild` provisioning updates plus cloud-managed distribution certificate access. After the current IPA passes local checks, the expected remaining blockers before submission are external: app-record creation, manual fields, upload/TestFlight processing, screenshot approval, legal/privacy review, and final real-account tap-through.

Do not commit private App Store Connect contact details, demo-account credentials, trader contact details, Apple IDs, API keys, issuer IDs, or `.p8` private keys.

If readiness reports a missing or stale IPA, make either Xcode distribution signing or `xcodebuild` API-key provisioning auth with cloud-managed distribution certificate access available, then run:

```sh
Scripts/app_store_signing_status.sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
```

The signing status script checks the local Xcode/App Store upload toolchain, whether an Apple Distribution/iOS Distribution identity is available for team `M4WTLM6RAQ`, and whether the native Mac App Store application and installer signing identities are available. A `Developer ID Application` identity is for direct macOS distribution and does not satisfy the iOS App Store IPA export gate or the native Mac App Store package gate.

The export script checks for Xcode 26 or later, an iOS 26 or newer SDK, and an Apple Distribution/iOS Distribution signing identity for team `M4WTLM6RAQ` before archiving. If `APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_API_ISSUER`, and `APP_STORE_CONNECT_P8_FILE` are all set, it passes those credentials to `xcodebuild` so automatic signing can authenticate with App Store Connect for provisioning updates. Those inputs make cloud signing attemptable; `xcodebuild -exportArchive` must still prove the account has cloud-managed distribution certificate access. It then stages archive/export output and replaces the current IPA folder only after export validation succeeds.

If export reports that the App Store provisioning profile lacks iCloud or `com.apple.developer.ubiquity-kvstore-identifier`, run `Scripts/upload_app_store_ipa.sh app-record` first. The REST check verifies both the Developer Portal bundle ID and the required `ICLOUD` bundle capability. If the capability is enabled, regenerate or download the App Store profile; if the capability is missing, enable iCloud key-value storage for `com.blakecrosley.captainslog` in Apple Developer/App Store Connect before regenerating the profile. Rerun `Scripts/app_store_signing_status.sh` before another export attempt.

If signing status still reports a missing distribution identity, either configure the App Store Connect API-key environment variables from `Docs/AppStoreConnectEnv.template.sh` and make sure that account has cloud-managed distribution certificate access, or open Xcode > Settings > Accounts, sign into an Apple ID that belongs to team `M4WTLM6RAQ`, select the team, open Manage Certificates, then use `+` > Apple Distribution. For native Mac App Store export, also create or install a Mac Installer Distribution certificate if Xcode does not create it automatically. If profiles still look stale afterward, use Download Manual Profiles and rerun `Scripts/app_store_signing_status.sh`.

## 1. Create Or Confirm The App Record

In the App Store Connect web UI, create or confirm:

- Platform: iOS
- Name: `Captain's Log`
- Primary language: English (U.S.)
- Bundle ID: `com.blakecrosley.captainslog`
- SKU: `captainslog-ios`
- Team: `M4WTLM6RAQ`

Evidence that closes this step:

```sh
Scripts/check_app_store_connect_record.py
```

Run the evidence command after API credentials are configured in step 4. It checks the App Store Connect REST API directly and does not need `APP_STORE_CONNECT_PROVIDER_PUBLIC_ID`. Current iOS evidence shows the Developer Portal bundle ID exists and the required `ICLOUD` bundle capability is enabled, but the App Store Connect app record is missing or not visible to this API key. Existing Return, ReturnTV, Return Watch, and Get Bananas Watch bundle IDs prove the 941 team pattern: exact Developer Portal bundle IDs, `platform: UNIVERSAL`, and `ICLOUD` enabled where the app entitlements require it. They do not create or cover Captain's Log records. Apple's `apps` API documentation describes the API as a management surface for existing apps, not the supported path for creating new app records, so the Captain's Log iOS app record remains a web-UI gate followed by read-only REST verification. If App Store Connect gives an Apple ID for this app after creation, keep it locally as `APP_STORE_CONNECT_APPLE_ID` for status checks. Do not commit it unless you intentionally decide it is safe to document.

For native Mac, Watch, and TV, current evidence reports the three Captain's Log Developer Portal bundle IDs are missing or not visible to this API key. Preview that account work without mutating the account:

```sh
Scripts/ensure_platform_bundle_ids.py
```

That script is dry-run by default. After confirming the account/team context, `Scripts/ensure_platform_bundle_ids.py --apply --confirm-team M4WTLM6RAQ` creates the missing platform bundle IDs and enables the entitlement-derived `ICLOUD` capability. The helper refuses `--apply` unless the existing iOS bundle ID is visible under team `M4WTLM6RAQ`. It still does not create the iOS App Store Connect app record; that remains a web-UI step.

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
- Apple Watch / Apple TV availability: no action for the first release unless the new companion targets are intentionally finished.
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
- Mac: do not enable the iPhone/iPad app on Apple Silicon Mac for the first release, and do not submit the native macOS target until the native Mac Developer Portal bundle ID and required capabilities exist, `Scripts/smoke_macos_launch.sh /tmp/captainslog-macos-smoke`, `CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export`, screenshot marketing acceptance, TestFlight, and human QA are complete.
- Apple Watch and Apple TV: no action in App Store Connect for this release unless the companion targets are intentionally finished. They now compile and launch in unsigned simulator smokes as Captain's Log targets, have an aggregate snapshot data path, include platform icon/top-shelf assets, and produce local App Store screenshot artifacts, but still need Developer Portal bundle IDs, required capabilities, signed export, TestFlight, provisioning validation, human screenshot acceptance, and platform QA before availability.

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
# Optional when the matching AuthKey_<key>.p8 file exists in ~/.appstoreconnect/private_keys.
# export APP_STORE_CONNECT_P8_FILE="/absolute/path/to/AuthKey_....p8"
```

`Docs/AppStoreConnectEnv.template.sh` contains a safe placeholder-only shell template for these exports plus provider/status variables. Do not enter real credentials in the tracked file; copy the placeholder exports into a private shell session or `AppStoreConnectEnv.local.sh`, which is gitignored and automatically loaded by the release scripts and App Store Connect REST checker from either the repo root or `Docs/`. You can also point `CAPTAINS_LOG_APP_STORE_CONNECT_ENV_FILE` at another private shell file.

If you are reusing an App Store Connect key already used by another 941 app, do not point Captain's Log at a `.p8` file inside that app's repository or Fastlane folder. The credential guard intentionally rejects private keys inside any git working tree. Select the matching key in App Store Connect, then stage a private local copy at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` with owner-only permissions.

If `Scripts/app_store_signing_status.sh` reports that candidate `.p8` private-key files are already staged, choose the matching App Store Connect key ID in Apple, then either leave the matching file at `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` or point `APP_STORE_CONNECT_P8_FILE` at that staged path. Multiple staged candidates are fine only after the key ID is selected; before that, the scripts cannot know which key belongs to Captain's Log:

Apple shows team key IDs in App Store Connect under Users and Access > Integrations, in the Active keys table. The issuer UUID appears near the top of that same Integrations page.

If you are copying the pattern from Return or Get Bananas, Captain's Log now accepts their Fastlane aliases directly when the canonical variables are unset:

```sh
export ASC_KEY_ID="<KEY_ID>"
export ASC_ISSUER_ID="<ISSUER_UUID>"
# Optional when the matching file exists in ~/.appstoreconnect/private_keys.
# export ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8"
```

Only set `ASC_KEY_PATH` after confirming it points outside every git working tree. If it points at another app's `fastlane/AuthKey_*.p8`, copy the matching file into `~/.appstoreconnect/private_keys/` first and use that private path for Captain's Log.

```sh
export APP_STORE_CONNECT_API_KEY="<KEY_ID>"
export APP_STORE_CONNECT_API_ISSUER="<ISSUER_UUID>"
# Optional when the matching file exists in ~/.appstoreconnect/private_keys.
# export APP_STORE_CONNECT_P8_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8"
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

Then run `Scripts/upload_app_store_ipa.sh app-record` or `Scripts/check_app_store_connect_record.py` to confirm the App Store Connect app record by bundle ID and the required bundle capabilities. Set `APP_STORE_CONNECT_PROVIDER_PUBLIC_ID` only if you need the older `Scripts/upload_app_store_ipa.sh app-record-altool` path; Xcode 26.5 `altool --list-providers` does not support API-key authentication, so obtain this value from App Store Connect, Transporter, or a manually authenticated altool session. Evidence that closes this step: readiness shows API key/issuer and `.p8` as valid, the REST app-record check reports an app record for `com.blakecrosley.captainslog`, reports required bundle capabilities enabled, and no App Store private key material exists inside this repo or another git working tree.

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
