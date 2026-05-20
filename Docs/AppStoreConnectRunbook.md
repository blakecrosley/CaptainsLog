# Captain's Log App Store Connect Runbook

Use this during the first App Store Connect/TestFlight session. It is the short operator path; keep `Docs/PlatformExpansionPlan.md` open for the platform verdict, `Docs/AppStoreConnectSubmission.md` open for evidence, `Docs/AppStoreCompletionAudit.md` open for gate status, and `Docs/AppStoreMetadata.md` open for paste-ready copy.

## Start Here

From the repo root:

```sh
CAPTAINS_LOG_SKIP_MEDIA_CHECKS=1 Scripts/app_store_readiness_status.sh
Scripts/print_app_store_account_action_packet.py
Scripts/print_platform_readiness_matrix.py
Scripts/print_platform_readiness_matrix.py --require-local
Scripts/print_platform_readiness_matrix.py --platform ipad --platform vision --require-local
```

Use the no-media summary as the gate when the goal is signing/account/export readiness. Use `Scripts/print_app_store_account_action_packet.py` as the operator packet for the App Store Connect web-UI/profile session; it composes the current source-custody, app-record, bundle-ID, profile, remote-signing, and platform-matrix checks without creating account state. If readiness reports Kit941 source drift, push or explicitly accept the linked package state before final export because Captain's Log links `../941Kit` directly and the export manifest records that package commit and dirty state. If readiness only reports the known missing/stale IPA state after source custody is settled, regenerate/download the active App Store profile and make one export-signing path complete, then regenerate the IPA before continuing into App Store Connect. The two supported signing paths are a local Apple Distribution/iOS Distribution identity/profile pair for team `M4WTLM6RAQ`, or App Store Connect API-key env vars for `xcodebuild` provisioning updates plus cloud-managed distribution certificate access. After the current IPA passes local checks, the expected remaining blockers before submission are external: app-record creation, manual fields, upload/TestFlight processing, store-media acceptance, legal/privacy review, and final real-account tap-through.

For the first iPhone/iPad plus compatible Apple Vision Pro release path, use `Scripts/print_platform_readiness_matrix.py --platform ipad --platform vision --require-store` after signed export, upload/TestFlight processing, App Store Connect availability setup, store-media acceptance, and final tap-through. Omit `--platform` only when intentionally requiring native Mac, Apple Watch, and Apple TV store readiness too.

Do not commit private App Store Connect contact details, demo-account credentials, trader contact details, Apple IDs, API keys, issuer IDs, or `.p8` private keys.

## Current Account Action Packet

Use this packet for the next App Store Connect / Apple Developer session. It is intentionally narrow: it closes the account/signing blockers that current read-only checks report, without creating separate Mac or TV bundle IDs.

1. Create or confirm the App Store Connect app record in the App Store Connect web UI. Apple documents this as a web-UI step before build upload, with Account Holder, App Manager, or Admin role required:
   - Platform: iOS
   - Name: `Captain's Log`
   - Bundle ID: `com.blakecrosley.captainslog`
   - SKU: `captainslog-ios`
   - Primary language: English (U.S.)
   - Team: `M4WTLM6RAQ`

   Official reference: https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/

   Evidence command after the web-UI action:

   ```sh
   Scripts/check_app_store_connect_record.py
   ```

2. Create the Watch companion bundle ID only after explicit Apple account mutation approval:

   Dry run:

   ```sh
   Scripts/ensure_platform_bundle_ids.py --target watchos
   ```

   Apply after approval:

   ```sh
   Scripts/ensure_platform_bundle_ids.py --target watchos --apply --confirm-team M4WTLM6RAQ
   ```

   The latest dry run plans only `com.blakecrosley.captainslog.watchkitapp` plus `ICLOUD`. Do not create `com.blakecrosley.captainslog.mac` or `com.blakecrosley.captainslog.tv`. Apple's add-platform guidance says macOS, tvOS, and visionOS platform versions added to the same app record use the same Apple ID, SKU, and bundle ID as the iOS app. Current Captain's Log Mac and TV targets share `com.blakecrosley.captainslog`, and the dry-run currently reports that shared bundle ID exists with required capabilities for both Mac and TV.

   Official reference: https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms

3. Make distribution signing/export possible:
   - iOS and TV need an active App Store distribution certificate/profile path for `com.blakecrosley.captainslog`.
   - Native Mac needs Mac App Store application and installer distribution certificate/profile paths for `com.blakecrosley.captainslog`.
   - Watch needs the companion bundle ID created first; signed export/TestFlight remains the release authority for the Watch path.

   Evidence commands:

   ```sh
   Scripts/app_store_signing_status.sh
   Scripts/check_remote_signing_assets.py --require
   Scripts/ensure_app_store_profiles.py --target ios
   ```

   Dry-run profile creation before mutating account state:

   ```sh
   Scripts/ensure_app_store_profiles.py --target ios
   Scripts/ensure_app_store_profiles.py --target ios --download-existing
   Scripts/ensure_app_store_profiles.py --target ios --apply --confirm-team M4WTLM6RAQ
   ```

   For Mac/TV readiness, run the same helper with `--target macos` or `--target tvos` after the shared app record path is accepted. The helper creates profiles only after `--apply --confirm-team M4WTLM6RAQ`; without `--apply`, it is read-only unless `--download-existing` is used to install an already-active remote profile into Xcode's local provisioning profile directory.

4. Regenerate release artifacts only after the signing checks above are green enough to prove the real export path:

   ```sh
   CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
   CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export
   CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_watchos_app_store_ipa.sh /tmp/captainslog-current-watchos-appstore-export
   CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_tvos_app_store_ipa.sh /tmp/captainslog-current-tvos-appstore-export
   Scripts/app_store_readiness_status.sh
   ```

Do not treat this packet as platform approval. iPad and Vision are local iOS availability paths until the signed iOS upload is processed. Native Mac, Watch, and TV still need signed export, TestFlight, platform QA, provisioning validation, and store-media acceptance before enabling store availability.

If readiness reports a missing or stale IPA, regenerate/download the active App Store profile and make either Xcode distribution signing or `xcodebuild` API-key provisioning auth with cloud-managed distribution certificate access available, then run:

```sh
Scripts/app_store_signing_status.sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
```

The signing status script checks the local Xcode/App Store upload toolchain, whether an Apple Distribution/iOS Distribution identity is available for team `M4WTLM6RAQ`, and whether the native Mac App Store application and installer signing identities are available. A `Developer ID Application` identity is for direct macOS distribution and does not satisfy the iOS App Store IPA export gate or the native Mac App Store package gate.

For read-only remote evidence before another export attempt, run:

```sh
Scripts/check_app_store_account_access.py
Scripts/check_remote_signing_assets.py --require
```

`Scripts/check_app_store_account_access.py` queries App Store Connect user visibility plus one aggregate app-list page, and prints only aggregate role/all-app/provisioning/app counts. It intentionally omits user names, emails, app names, bundle IDs, resource IDs, and API-key material. Passing this check proves the selected API credential can read account user visibility and list existing apps; visible role aggregates are still not selected-key proof, and the check does not prove Captain's Log app-record creation, signing-asset creation, or cloud-managed distribution certificate access. Apple's `CREATE_APPS` role is directly relevant to app-record creation, and `CLOUD_MANAGED_APP_DISTRIBUTION` is the cloud-managed Apple Distribution permission, but App Store Connect web UI verification and `xcodebuild -exportArchive` remain the authorities for whether the selected account path can actually use them.

This checks visible App Store Connect certificate/profile resources, target-specific certificate groups, and the expected App Store profile types for Captain's Log bundle IDs. It does not create certificates, profiles, bundle IDs, or app records. Apple's current Profile API documents iOS, Mac, tvOS, and Mac Catalyst profile types but no dedicated watchOS App Store profile type, so the checker keeps Watch signing incomplete until signed export/TestFlight proves the path. Visible remote assets still do not prove local private-key access or cloud-managed distribution certificate permission; `xcodebuild -exportArchive` remains the authority for final export readiness.

The iOS export script checks for Xcode 26 or later, an iOS 26 or newer SDK, and an Apple Distribution/iOS Distribution signing identity for team `M4WTLM6RAQ` before archiving. If `APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_API_ISSUER`, and `APP_STORE_CONNECT_P8_FILE` are all set, it passes those credentials to `xcodebuild` so automatic signing can authenticate with App Store Connect for provisioning updates. Those inputs make cloud signing attemptable; `xcodebuild -exportArchive` must still prove the account has cloud-managed distribution certificate access. It then stages archive/export output and replaces the current IPA folder only after export validation succeeds.

The Watch and TV export helpers follow the same staging, credential-custody, and clean-source rules for their companion targets. They should remain dormant for the first submission unless those platforms are intentionally included; Watch still needs `com.blakecrosley.captainslog.watchkitapp` created with iCloud capability, and TV still needs an active `TVOS_APP_STORE` profile for the shared `com.blakecrosley.captainslog` bundle ID.

If a failed export creates an `.xcdistributionlogs` bundle, inspect only the minimal error excerpts needed for diagnosis and do not commit, paste, or preserve the raw bundle. Xcode distribution logs can include transient App Store Connect bearer tokens in request headers; delete generated temp log bundles after extracting the non-secret error cause.

If export reports that the App Store provisioning profile lacks iCloud or `com.apple.developer.ubiquity-kvstore-identifier`, run `Scripts/upload_app_store_ipa.sh app-record` first. The REST check verifies both the Developer Portal bundle ID and the required `ICLOUD` bundle capability. If the capability is enabled, regenerate or download the App Store profile; if the capability is missing, enable iCloud key-value storage for `com.blakecrosley.captainslog` in Apple Developer/App Store Connect before regenerating the profile. Rerun `Scripts/app_store_signing_status.sh` before another export attempt.

Current signing status shows a local Apple Distribution identity for team `M4WTLM6RAQ`, so the next iOS signing action is to regenerate or download an active App Store provisioning profile for `com.blakecrosley.captainslog`, then rerun `Scripts/app_store_signing_status.sh`. Xcode 26.5 does not expose an `xcodebuild -downloadAllProvisioningProfiles` command; the CLI path is `-allowProvisioningUpdates`, which can create or update Apple Developer resources for automatically signed targets, so use the Xcode UI's Download Manual Profiles action when the intent is only to refresh local profile files. If signing status later reports a missing distribution identity, either configure the App Store Connect API-key environment variables from `Docs/AppStoreConnectEnv.template.sh` and make sure that account has cloud-managed distribution certificate access, or open Xcode > Settings > Accounts, sign into an Apple ID that belongs to team `M4WTLM6RAQ`, select the team, open Manage Certificates, then use `+` > Apple Distribution. For native Mac App Store export, also create or install a Mac Installer Distribution certificate if Xcode does not create it automatically. If profiles still look stale afterward, use Download Manual Profiles and rerun `Scripts/app_store_signing_status.sh`.

Signing evidence that closes this step: `Scripts/check_remote_signing_assets.py --require` reports the required certificate groups and active App Store profile types for the selected targets, then `CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export` produces both the IPA and `ExportManifest.txt`. If native Mac is intentionally included, `CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export` must also produce a signed package and `MacExportManifest.txt`. If Watch or TV are intentionally included, `Scripts/export_watchos_app_store_ipa.sh` and `Scripts/export_tvos_app_store_ipa.sh` must produce their signed IPAs plus `WatchExportManifest.txt` and `TvOSExportManifest.txt`.

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

Run the evidence command after API credentials are configured in step 4. It checks the App Store Connect REST API directly and does not need `APP_STORE_CONNECT_PROVIDER_PUBLIC_ID`. Current iOS evidence shows the Developer Portal bundle ID exists and the required `ICLOUD` bundle capability is enabled, but `appRecordLookupMethod: bundle-id-relationship-empty` shows no App Store Connect app record is attached to that exact bundle ID. The checker also reports visible matches for the expected SKU `captainslog-ios` and name `Captain's Log`; current evidence reports zero visible matches for both, so this is not just an exact-bundle mismatch. Existing Return and Get Bananas records prove useful 941 account precedent, but they do not create or cover Captain's Log records. Apple's App Store Connect help says a new app record is created in App Store Connect before upload, and Apple's App Store Connect API `apps` resource documentation says not to use that API to create new apps. The Captain's Log iOS app record therefore remains a web-UI gate followed by read-only REST verification. If App Store Connect gives an Apple ID for this app after creation, keep it locally as `APP_STORE_CONNECT_APPLE_ID` for status checks. Do not commit it unless you intentionally decide it is safe to document.

For native Mac, Watch, and TV, do not blindly create separate bundle IDs. Apple's current single-record/universal-purchase guidance says added macOS, tvOS, and visionOS platform versions share the iOS app's bundle ID, while Apple Watch distribution starts from an iOS app with watchOS counterpart information and screenshots. The local 941 precedents match that pattern: ReturnTV uses `com.941apps.Return`, and Get Bananas uses `com.941apps.Banana-List` for its main iOS/Mac target. Captain's Log Mac and TV now share `com.blakecrosley.captainslog`; the Watch companion precedent is different and uses a `.watchkitapp` bundle ID.

Preview the account work without mutating the account:

```sh
Scripts/ensure_platform_bundle_ids.py
```

That script is dry-run by default. For the Watch companion, only run `Scripts/ensure_platform_bundle_ids.py --target watchos --apply --confirm-team M4WTLM6RAQ` after explicit approval to mutate Apple Developer/App Store Connect state; git push approval is not account-mutation approval. The helper refuses `--apply` unless the existing iOS bundle ID is visible under team `M4WTLM6RAQ`, and it rechecks exact bundle/capability visibility after mutation. Mac and TV use the shared iOS bundle ID and should not create separate `.mac` or `.tv` bundle IDs unless a future separate app-record strategy is intentionally chosen with the additional `--confirm-separate-platform-records` flag. The script still does not create the iOS App Store Connect app record; that remains a web-UI step.

## 2. Enter Product Metadata

Use `Docs/AppStoreMetadata.md`.

For a paste-focused, no-mutation packet generated from the current metadata source, run:

```sh
Scripts/print_app_store_entry_packet.py
```

For a machine-readable packet or a pre-session validation check, run:

```sh
Scripts/print_app_store_entry_packet.py --json
Scripts/print_app_store_entry_packet.py --check
```

No-screenshot metadata pass:

- Use the existing reviewed media package for any App Store media upload prompt.
- Do not regenerate screenshots during the account/signing/metadata session.
- Keep the platform claim to iPhone and iPad, with Apple Vision Pro only through the compatible iPhone/iPad availability path after signed iOS upload and final acceptance.
- Do not market native Mac, Apple Watch, or Apple TV until signed export, TestFlight, platform QA, provisioning validation, and store-media acceptance are complete.

Enter the paste-ready fields:

- Name, subtitle, category, SKU, bundle ID.
- Privacy Policy URL and Support URL.
- Promotional text, description, keywords.
- App Review notes.

Held platform copy lives in `Docs/AppStoreMarketingPacket.md`. Use it only after the matching native Mac, Watch, or TV gates close. For Mac and TV platform versions, App Store Connect may transfer some existing metadata from the iOS version, but promotional text, description, and screenshots still need platform-specific review. For Watch, include Apple Watch functionality in the submitted description and provide the required Watch media/icon only after the Watch bundle/signing/TestFlight path is complete.

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
- Apple Vision Pro: make available as the compatible iPhone/iPad app after `CAPTAINS_LOG_SKIP_SMOKE_SCREENSHOTS=1 Scripts/smoke_vision_compatible_launch.sh /tmp/captainslog-vision-smoke` still builds, installs, and launches. Do not add native visionOS screenshots or metadata unless a separate visionOS target exists.
- Mac: do not enable the iPhone/iPad app on Apple Silicon Mac for the first release, and do not submit the native macOS target until the shared bundle ID and required capabilities are verified for the Mac path, `Scripts/smoke_macos_launch.sh /tmp/captainslog-macos-smoke`, `CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export`, store-media acceptance, TestFlight, and human QA are complete.
- Apple Watch and Apple TV: no action in App Store Connect for this release unless the companion targets are intentionally finished. They now compile and launch in unsigned simulator smokes as Captain's Log targets, have an aggregate snapshot data path, include platform icon/top-shelf assets, and have guarded export helpers. Watch still needs its Developer Portal companion bundle ID and iCloud capability created after explicit account-mutation approval. Apple TV uses the existing shared `com.blakecrosley.captainslog` bundle ID, so its remaining blockers are signed export through `Scripts/export_tvos_app_store_ipa.sh`, TestFlight, provisioning validation, living-room QA, and store-media acceptance before availability.

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

Then run `Scripts/upload_app_store_ipa.sh app-record` or `Scripts/check_app_store_connect_record.py` to confirm the App Store Connect app record by bundle ID, expected SKU/name, and the required bundle capabilities. Set `APP_STORE_CONNECT_PROVIDER_PUBLIC_ID` only if you need the older `Scripts/upload_app_store_ipa.sh app-record-altool` path; Xcode 26.5 `altool --list-providers` does not support API-key authentication, so obtain this value from App Store Connect, Transporter, or a manually authenticated altool session. Evidence that closes this step: readiness shows API key/issuer and `.p8` as valid, the REST app-record check reports an app record for `com.blakecrosley.captainslog` with expected SKU `captainslog-ios` and name `Captain's Log`, reports required bundle capabilities enabled, and no App Store private key material exists inside this repo or another git working tree.

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

## 6. Store Media Acceptance

For the current no-screenshot path, do not regenerate screenshots. Use the existing packaged folders if App Store Connect asks for media, then leave final media acceptance as a human approval gate. If a later marketing pass explicitly reopens screenshot work, run the capture, preflight, package, contact-sheet, and screenshot text-audit commands from `Docs/AppStoreConnectSubmission.md`. The package and review scripts stage output first, then replace the current upload/review folders only after generation succeeds, so a failed regeneration should leave the last reviewed screenshots intact.

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

Before upload, either use App Store Connect's own media previews or open the existing local review packet:

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
