# Captain's Log App Store Completion Audit

Audit date: May 18, 2026

This audit restates the current objective as concrete completion criteria and maps each criterion to the evidence that exists today. It is intentionally stricter than a progress summary: if a requirement needs App Store Connect, signing, legal review, or human approval, it remains open.

## Completion Criteria

Captain's Log is ready for the first App Store Connect/TestFlight pass only when:

1. The current source tree, linked Kit941 package, metadata, privacy manifest, screenshots, and release helper scripts are locally verified.
2. A current App Store Connect IPA exists from clean source and passes local release checks.
3. App Store Connect API credentials and distribution signing are available outside the repo.
4. The App Store Connect app record exists and matches the bundle ID.
5. Product metadata, privacy answers, screenshots, and review notes are entered and accepted by App Store Connect.
6. The build validates, uploads, and finishes TestFlight processing.
7. The screenshot/design set receives human approval.
8. Legal/privacy review and final real-account tap-through are complete.

## Prompt-To-Artifact Checklist

| Requirement | Artifact or command | Current evidence | Status |
| --- | --- | --- | --- |
| Prepare for App Store Connect | `Docs/AppStoreConnectRunbook.md`, `Docs/AppStoreConnectSubmission.md`, `Docs/AppStoreReadiness.md` | Runbook, evidence packet, metadata, privacy answers, screenshot packet, export helper, upload helper, and readiness script exist. Readiness verifies CaptainsLog and linked Kit941 source cleanliness and upstream sync before submission work. | Partially complete |
| Clean up UI | `/tmp/captainslog-appstore-review/contact-sheet.png`, `/tmp/captainslog-key-state-audit`, `Docs/AppStoreDesignReview.md`, `Scripts/audit_app_store_screenshot_text.sh /tmp/captainslog-key-state-packaged` | Screenshot packet shows dashboard, Work Map, journal, repositories, AI providers, and Privacy & Data on iPhone and iPad. The dashboard uses the compact selected-period menu instead of a second full-width segmented control, the demo journal copy no longer exposes `fixture`/`UI Fixture` wording, and the repeatable screenshot text audit found no debug, simulator, sync-progress, error, personal-account, or token-like text in the regenerated packaged screenshots. | Locally acceptable, human approval open |
| Make design review happy | `.impeccable.md`, `Docs/AppStoreDesignReview.md` | Design context says quiet, precise, journal-like, Apple-native, with Work Map as the identity surface. Design review score is 33/40, the latest spot-check says the dashboard control weight improved, and the review recommends no major new features before first TestFlight unless human screenshot approval finds a concrete issue. | Locally acceptable |
| Metadata and manual App Store fields | `Docs/AppStoreMetadata.md` | Name, subtitle, description, keywords, URLs, review notes, screenshot order, price/distribution/release recommendations, platform-availability recommendations, and manual App Store Connect choices are documented. | Paste-ready, App Store entry open |
| Privacy answers | `Docs/AppStorePrivacyAnswers.md`, `Docs/PrivacyPolicyDraft.md`, `Docs/SupportPageDraft.md` | Privacy questionnaire draft exists; published support/privacy URLs passed preflight content checks. Legal review remains recommended. | Locally ready, legal review open |
| Required reason API and privacy manifest | `Scripts/privacy_required_reason_audit.sh`, `CaptainsLog/Resources/PrivacyInfo.xcprivacy` | Latest readiness run passed required-reason audit and preflight confirmed UserDefaults reason `CA92.1`. | Complete locally |
| App icons, screenshots, and release plist surface | `Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit`, `Scripts/app_store_readiness_status.sh` | Preflight passed icon dimensions, all app icon alpha-channel checks, source iPhone/iPad screenshot dimensions, export-compliance flag, privacy manifest, and background-processing task identifier consistency. Readiness also verifies the packaged upload folders contain the exact six expected screenshot filenames per family with 6.9-inch iPhone and accepted 13-inch iPad dimensions. | Complete locally |
| Preserve screenshot package/review artifacts on failed regeneration | `Scripts/package_app_store_screenshots.sh`, `Scripts/make_app_store_screenshot_contact_sheet.sh` | Both scripts now generate into staged temporary folders and replace the current package/review output only after generation succeeds. Smoke tests produced the 12-PNG package plus review HTML/contact sheet, and simulated missing-screenshot failures preserved the existing output folder. | Complete locally |
| Current release IPA | `CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export` | The export script now checks Xcode 26+, iOS 26+ SDK, and distribution signing for team `M4WTLM6RAQ` before archiving. It can also pass `APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_API_ISSUER`, and `APP_STORE_CONNECT_P8_FILE` to `xcodebuild` for App Store Connect-authenticated provisioning updates when those env vars are set. Current local export remains blocked because neither a local Apple Distribution/iOS Distribution identity nor App Store Connect API credentials are available. The previous IPA is stale after app icon resources changed; readiness also fails if an archive-only output exists without the matching export manifest so stale development-signed archives are not mistaken for release output. | Blocked |
| Preserve existing IPA on failed export | `Scripts/export_app_store_ipa.sh` | Temp preservation test kept an existing dummy IPA and manifest after the expected signing failure. The script now stages archive, IPA, and export manifest together and only replaces current export output after validation and manifest creation succeed. | Complete locally |
| Upload helper local checks | `Scripts/upload_app_store_ipa.sh local-check <ipa>` | Helper validates bundle ID, privacy manifest, encryption flag, `get-task-allow=false`, clean export manifest, and debug/test fixture strings, including screenshot hooks and UI-testing launch hooks. It cannot pass until a current IPA exists. | Script ready, IPA blocked |
| App Store Connect app record check | `Scripts/upload_app_store_ipa.sh providers`, `Scripts/upload_app_store_ipa.sh app-record` | Helper no longer requires an IPA for `app-record`. It now fails unless the filtered `altool --list-apps` output actually contains bundle ID `com.blakecrosley.captainslog`. Current run fails before contacting Apple because `APP_STORE_CONNECT_API_KEY` and `APP_STORE_CONNECT_API_ISSUER` are not set; after API credentials are available, `providers` must be used to set `APP_STORE_CONNECT_PROVIDER_PUBLIC_ID` because Xcode 26.5 `altool --list-apps` requires a provider public ID. | Blocked on credentials |
| App Store Connect API key custody | `Scripts/upload_app_store_ipa.sh credential-guard-self-test`, `Scripts/app_store_readiness_status.sh` | Credential guard self-test passed. Readiness confirms no `.p8` private-key material is in the repo. | Complete locally, real credentials open |
| Source token-literal hygiene | `Scripts/app_store_readiness_status.sh` | Readiness scans the app, tests, docs, and scripts for OpenAI/Anthropic/GitHub-token-shaped literals and currently reports `no token-shaped source literals found`. Screenshot and test fixtures construct fake key values at runtime instead of storing token-shaped source strings. | Complete locally |
| Distribution signing | `Scripts/app_store_signing_status.sh`, `security find-identity -v -p codesigning`, `Scripts/export_app_store_ipa.sh`, and readiness script | The signing status script checks Xcode 26+, iOS 26+ SDK, and local signing state. Current keychain has Apple Development and Developer ID Application identities, but no Apple Distribution/iOS Distribution identity. The export script now supports either a local distribution identity or App Store Connect API-key authentication for xcodebuild provisioning updates, but the required API env vars are not set in the current shell. | Blocked |
| Validate/upload/status | `Scripts/upload_app_store_ipa.sh validate`, `upload`, `status` | Cannot run until a current IPA exists and App Store Connect credentials are set. | Blocked |
| Final App Store Connect entry | App Store Connect web UI, `Docs/AppStoreConnectRunbook.md` | Manual fields, regional prompts, Apple Vision Pro availability, Apple Silicon Mac availability, EU DSA trader status, tax category if shown, demo/review contact, screenshot upload, processed build selection, and the final before-Add-for-Review warning check are not verifiable locally. | Human/App Store gate |
| Linked package source custody | `Scripts/app_store_readiness_status.sh`, `git -C ../941Kit status --short --branch`, `git -C ../941Kit rev-parse --short=12 HEAD` | Kit941 package source is clean, synced with `origin/main`, and currently at `69dcc9be7d06`. | Complete locally |
| Current-head simulator tests | `xcodebuild test -project CaptainsLog.xcodeproj -scheme CaptainsLog-iOS -destination 'id=277C8808-F02C-43A4-8B4A-11BA187F0788' -derivedDataPath /tmp/captainslog-demo-path-unit-tests -only-testing:CaptainsLogTests`, `xcodebuild test -project CaptainsLog.xcodeproj -scheme CaptainsLog-iOS -destination 'id=277C8808-F02C-43A4-8B4A-11BA187F0788' -derivedDataPath /tmp/captainslog-demo-path-ui-tests -only-testing:CaptainsLogUITests` | Current source passed 69 unit tests and 3 UI tests with 0 failures on the iOS 26.5 iPhone 17 simulator. The UI tests cover first-run primary actions, the production Use Demo Data tap-through into dashboard and journal detail, fixture dashboard, Settings, Privacy & Data, and selected-day journal detail. | Complete locally |
| Current-head unsigned device archive | `xcodebuild archive -project CaptainsLog.xcodeproj -scheme CaptainsLog-iOS -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/captainslog-current-nosign-archive.xcarchive -derivedDataPath /tmp/captainslog-current-nosign-archive-derived CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''` | The May 18, 2026 archive succeeded from current source with the linked local `Kit941` package. The archived app metadata reported bundle ID `com.blakecrosley.captainslog`, version `1.0.0 (1)`, `ITSAppUsesNonExemptEncryption=false`, `PrivacyInfo.xcprivacy` present, and `Assets.car` present. This proves current source/package/resources archive for device, but it is unsigned and does not replace the signed App Store IPA/export-manifest gate. | Complete as compile/package proof; signed IPA still blocked |
| Release simulator string scan | `xcodebuild build -project CaptainsLog.xcodeproj -scheme CaptainsLog-iOS -configuration Release -destination 'id=277C8808-F02C-43A4-8B4A-11BA187F0788' -derivedDataPath /tmp/captainslog-demo-path-release`, `strings <Release app executable>` | Release simulator build succeeded on the iOS 26.5 iPhone 17 simulator. The built executable did not contain the debug/test fixture strings that the future IPA `local-check` rejects, including screenshot hooks, debug OpenAI key seeding hooks, UI-testing hooks, and the screenshot demo key. Bundle metadata also showed the expected bundle ID, version/build, export-compliance flag, and privacy manifest. | Complete locally; signed IPA local-check still required |
| Final product QA | Real account on device, `xcodebuild test -project CaptainsLog.xcodeproj -scheme CaptainsLog-iOS -destination 'id=00008150-00166D690EF0401C' -derivedDataPath /tmp/captainslog-current-device-uitests -only-testing:CaptainsLogUITests` | Existing device-store audit verified local aggregate coverage. The latest current-head connected-phone UI-test attempt built and code signed the app plus UI-test runner with Apple Development, then stopped before launch at `Unlock Blake's iPhone 17 Pro Max (current) to Continue`; the hanging run was interrupted after the destination remained locked. Final real-account tap-through remains open. | Human/device gate |

## Latest Readiness Result

`Scripts/app_store_readiness_status.sh` from clean `main` currently:

- Passes command availability, Xcode/iOS SDK check, source cleanliness, screenshot packet checks, screenshot text audit, preflight, required-reason audit, and credential-guard self-test.
- Confirms both CaptainsLog and Kit941 are clean and synced with upstream.
- Reports no App Store private keys inside the repo.
- Reports no OpenAI, Anthropic, or GitHub token-shaped source literals in app, test, doc, or script files.
- Uses staged screenshot package/review scripts so failed screenshot regeneration does not erase the last reviewed artifacts.
- Has current device-test evidence showing the latest connected-phone UI-test attempt built and signed but could not launch while the phone was locked.
- Has current generic iOS Release archive evidence showing the app and linked `Kit941` package compile and package for device when code signing is disabled.
- Fails local readiness because the current IPA and export manifest are missing; readiness now skips IPA local-check until a current IPA exists so the missing IPA is not counted twice.
- A bypassed signing-precheck export attempt archived the generic iOS build, but the App Store export failed with `No Accounts` and `No signing certificate "iOS Distribution" found`, confirming the missing IPA cannot be fixed locally until either Xcode account/distribution signing or App Store Connect API-key provisioning auth is configured.
- Reports external blockers for export signing, App Store Connect API credentials, provider public ID, app record confirmation, manual App Store Connect fields including platform availability, upload/TestFlight processing, screenshot approval, legal/privacy review, and final real-account tap-through.

## Next Action

The next meaningful action is not more local feature work. Make one App Store export-signing path available, then regenerate the current IPA. Either configure Xcode account/distribution signing or set the App Store Connect API-key env vars from `Docs/AppStoreConnectEnv.template.sh`:

```sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
```

After that passes, rerun:

```sh
Scripts/app_store_signing_status.sh
Scripts/app_store_readiness_status.sh
Scripts/upload_app_store_ipa.sh local-check "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
Scripts/upload_app_store_ipa.sh providers
export APP_STORE_CONNECT_PROVIDER_PUBLIC_ID="..."
Scripts/upload_app_store_ipa.sh app-record
Scripts/upload_app_store_ipa.sh validate "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```
