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
| Prepare for App Store Connect | `Docs/AppStoreConnectRunbook.md`, `Docs/AppStoreConnectSubmission.md`, `Docs/AppStoreReadiness.md` | Runbook, evidence packet, metadata, privacy answers, screenshot packet, export helper, upload helper, and readiness script exist. | Partially complete |
| Clean up UI | `/tmp/captainslog-appstore-review/contact-sheet.png`, `/tmp/captainslog-key-state-audit`, `Docs/AppStoreDesignReview.md` | Screenshot packet shows dashboard, Work Map, journal, repositories, AI providers, and Privacy & Data on iPhone and iPad. No sync bar, debug labels, simulator chrome, or real private account data were visible in the reviewed artifacts. | Locally acceptable, human approval open |
| Make design review happy | `.impeccable.md`, `Docs/AppStoreDesignReview.md` | Design context says quiet, precise, journal-like, Apple-native, with Work Map as the identity surface. Design review score is 33/40 and recommends no major new features before first TestFlight unless human screenshot approval finds a concrete issue. | Locally acceptable |
| Metadata and manual App Store fields | `Docs/AppStoreMetadata.md` | Name, subtitle, description, keywords, URLs, review notes, screenshot order, price/distribution/release recommendations, and manual App Store Connect choices are documented. | Paste-ready, App Store entry open |
| Privacy answers | `Docs/AppStorePrivacyAnswers.md`, `Docs/PrivacyPolicyDraft.md`, `Docs/SupportPageDraft.md` | Privacy questionnaire draft exists; published support/privacy URLs passed preflight content checks. Legal review remains recommended. | Locally ready, legal review open |
| Required reason API and privacy manifest | `Scripts/privacy_required_reason_audit.sh`, `CaptainsLog/Resources/PrivacyInfo.xcprivacy` | Latest readiness run passed required-reason audit and preflight confirmed UserDefaults reason `CA92.1`. | Complete locally |
| App icons and screenshots | `Scripts/app_store_preflight.sh /tmp/captainslog-key-state-audit` | Preflight passed icon dimensions, all app icon alpha-channel checks, and all iPhone/iPad screenshot dimensions. | Complete locally |
| Current release IPA | `CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export` | Clean archive succeeds, but export fails because local Xcode lacks an App Store distribution account/certificate: `exportArchive No Accounts` and `No signing certificate "iOS Distribution" found`. The previous IPA is stale after app icon resources changed. | Blocked |
| Preserve existing IPA on failed export | `Scripts/export_app_store_ipa.sh` | Temp preservation test kept an existing dummy IPA and manifest after the expected signing failure. The script now stages outputs and only replaces current export output after validation succeeds. | Complete locally |
| Upload helper local checks | `Scripts/upload_app_store_ipa.sh local-check <ipa>` | Helper validates bundle ID, privacy manifest, encryption flag, `get-task-allow=false`, clean export manifest, and debug fixture strings. It cannot pass until a current IPA exists. | Script ready, IPA blocked |
| App Store Connect app record check | `Scripts/upload_app_store_ipa.sh app-record` | Helper no longer requires an IPA for `app-record`. Current run fails before contacting Apple because `APP_STORE_CONNECT_API_KEY` and `APP_STORE_CONNECT_API_ISSUER` are not set. | Blocked on credentials |
| App Store Connect API key custody | `Scripts/upload_app_store_ipa.sh credential-guard-self-test`, `Scripts/app_store_readiness_status.sh` | Credential guard self-test passed. Readiness confirms no `.p8` private-key material is in the repo. | Complete locally, real credentials open |
| Distribution signing | `security find-identity -v -p codesigning` and readiness script | Current keychain has Apple Development and Developer ID Application identities, but no Apple Distribution/iOS Distribution identity. Readiness reports this as an external blocker. | Blocked |
| Validate/upload/status | `Scripts/upload_app_store_ipa.sh validate`, `upload`, `status` | Cannot run until a current IPA exists and App Store Connect credentials are set. | Blocked |
| Final App Store Connect entry | App Store Connect web UI | Manual fields, regional prompts, EU DSA trader status, tax category if shown, demo/review contact, screenshot upload, and build selection are not verifiable locally. | Human/App Store gate |
| Final product QA | Real account on device | Existing device-store audit verified local aggregate coverage, but final real-account tap-through remains open. | Human/device gate |

## Latest Readiness Result

`Scripts/app_store_readiness_status.sh` from clean `main` currently:

- Passes command availability, Xcode/iOS SDK check, source cleanliness, screenshot packet checks, preflight, required-reason audit, and credential-guard self-test.
- Reports no App Store private keys inside the repo.
- Fails local readiness because the current IPA and export manifest are missing, so IPA local-check cannot run.
- Reports external blockers for distribution signing, App Store Connect API credentials, app record confirmation, manual App Store Connect fields, upload/TestFlight processing, screenshot approval, legal/privacy review, and final real-account tap-through.

## Next Action

The next meaningful action is not more local feature work. Make App Store distribution signing available in Xcode, then regenerate the current IPA:

```sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
```

After that passes, rerun:

```sh
Scripts/app_store_readiness_status.sh
Scripts/upload_app_store_ipa.sh local-check "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
Scripts/upload_app_store_ipa.sh app-record
Scripts/upload_app_store_ipa.sh validate "/tmp/captainslog-current-appstore-export/Export/Captain's Log.ipa"
```
