# Captain's Log

Captain's Log is an iPhone and iPad app for turning GitHub history into a private work journal. It connects to GitHub, imports selected repository history, shows a Work Map of commits or changed lines, and generates daily notes from the work evidence.

## App Store Connect Status

Start with the blocker-focused gate when the current work is account, signing, export, or platform readiness:

```sh
CAPTAINS_LOG_SKIP_MEDIA_CHECKS=1 Scripts/app_store_readiness_status.sh
```

For a concise no-screenshot account/signing session packet:

```sh
Scripts/print_app_store_account_action_packet.py
```

Use the full local gate only when product-page media artifacts are part of the pass:

```sh
Scripts/app_store_readiness_status.sh
```

As of the current App Store packet, the local metadata, marketing copy, privacy manifest, no-screenshot platform smokes, and helper scripts are ready for handoff, but the App Store path is still blocked until these external gates are closed:

- Create or make visible the App Store Connect app record for `com.blakecrosley.captainslog`; current REST evidence finds the Developer Portal bundle ID and required `ICLOUD` capability, but no app record by exact bundle, expected SKU `captainslog-ios`, or expected name `Captain's Log`.
- Regenerate or download an active App Store provisioning profile for `com.blakecrosley.captainslog`, then prove one iOS export signing path: App Store Connect API-key auth for `xcodebuild` provisioning updates plus cloud-managed distribution certificate access, or the local Apple Distribution/iOS Distribution identity for team `M4WTLM6RAQ`. Use `Scripts/ensure_app_store_profiles.py --target ios` as a dry-run plan before any profile mutation.
- Regenerate the signed IPA and `ExportManifest.txt`.
- Push or explicitly accept the CaptainsLog and linked `../941Kit` save points before final export; the latest readiness run reports both trees clean but not synced to `origin/main`.

Native Mac, Apple Watch, and Apple TV are separate platform gates. Mac and Apple TV now follow the single App Store record/universal-purchase bundle-ID model and share `com.blakecrosley.captainslog`; do not create separate `.mac` or `.tv` account state. Current REST evidence still reports the Captain's Log Watch companion bundle ID is missing or not visible. Native Mac App Store export additionally needs an active Mac App Store profile plus Mac installer signing proof, or the same App Store Connect API-key cloud signing path.

Current platform availability status:

- iPhone and iPad: locally prepared through the universal iOS app; not store-ready until a signed IPA is exported and uploaded.
- Apple Vision Pro: locally prepared through the compatible iPhone/iPad app path; not store-ready until signed upload, final acceptance, and App Store Connect availability selection are complete. This is not a native visionOS app.
- Mac: native target, local Release build, bundle metadata, launch, and quit proof exist; do not submit or market it until Mac signing/export, TestFlight, and human QA are complete.
- Apple Watch and Apple TV: companion targets exist, local no-screenshot launch proof exists, and the aggregate snapshot path is based on WatchConnectivity plus iCloud key-value sync. Do not submit or market them until signed export, TestFlight, provisioning validation, and platform QA are complete.

For the current platform verdict and the Watch/TV path after the first submission, use `Docs/PlatformExpansionPlan.md`.

Refresh the local Vision compatible-app smoke before final Vision acceptance:

```sh
CAPTAINS_LOG_SKIP_SMOKE_SCREENSHOTS=1 Scripts/smoke_vision_compatible_launch.sh /tmp/captainslog-vision-smoke
```

Refresh the local native Mac launch smoke before accepting Mac availability:

```sh
Scripts/smoke_macos_launch.sh /tmp/captainslog-macos-smoke
```

Refresh the local Watch/TV launch smokes before accepting the companion snapshot UI:

```sh
CAPTAINS_LOG_SKIP_SMOKE_SCREENSHOTS=1 Scripts/smoke_watchos_launch.sh /tmp/captainslog-watchos-smoke
CAPTAINS_LOG_SKIP_SMOKE_SCREENSHOTS=1 Scripts/smoke_tvos_launch.sh /tmp/captainslog-tvos-smoke
```

After active App Store provisioning profiles exist and either local distribution signing or API-key cloud signing is available:

```sh
Scripts/app_store_signing_status.sh
Scripts/ensure_app_store_profiles.py --target ios --download-existing
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
Scripts/app_store_readiness_status.sh
```

Before marketing the first iPhone/iPad plus compatible Vision path as available, after App Store Connect upload, TestFlight processing, and final acceptance are complete:

```sh
Scripts/print_platform_readiness_matrix.py --platform ipad --platform vision --require-store
```

If intentionally adding the native Mac target to this release:

```sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export
```

If intentionally adding the Watch or TV companion targets to this release, do this only after the matching bundle/signing/profile blockers are closed:

```sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_watchos_app_store_ipa.sh /tmp/captainslog-current-watchos-appstore-export
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_tvos_app_store_ipa.sh /tmp/captainslog-current-tvos-appstore-export
```

Before marketing every requested platform, including native Mac, Apple Watch, and Apple TV:

```sh
Scripts/print_platform_readiness_matrix.py --require-store
```

## Release Handoff

- Operator runbook: `Docs/AppStoreConnectRunbook.md`
- Platform verdict: `Docs/PlatformExpansionPlan.md`
- Completion audit: `Docs/AppStoreCompletionAudit.md`
- Submission evidence packet: `Docs/AppStoreConnectSubmission.md`
- Paste-ready metadata: `Docs/AppStoreMetadata.md`
- Marketing packet: `Docs/AppStoreMarketingPacket.md`
- Privacy answers: `Docs/AppStorePrivacyAnswers.md`
- Design review: `Docs/AppStoreDesignReview.md`

Do not commit App Store Connect contact details, demo credentials, API key IDs, issuer IDs, provider IDs, `.p8` private keys, provisioning profiles, certificates, exported IPAs, or archives.
