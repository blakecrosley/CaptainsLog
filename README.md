# Captain's Log

Captain's Log is an iPhone and iPad app for turning GitHub history into a private work journal. It connects to GitHub, imports selected repository history, shows a Work Map of commits or changed lines, and generates daily notes from the work evidence.

## App Store Connect Status

Start with the current gate:

```sh
Scripts/app_store_readiness_status.sh
```

For a blocker-focused pass that does not inspect screenshot/media artifacts:

```sh
CAPTAINS_LOG_SKIP_MEDIA_CHECKS=1 Scripts/app_store_readiness_status.sh
```

As of the current App Store packet, the local metadata, marketing copy, privacy manifest, and helper scripts are ready for handoff, but the App Store path is still blocked until these external gates are closed:

- Create or make visible the App Store Connect app record for `com.blakecrosley.captainslog`; current REST evidence finds the Developer Portal bundle ID and required `ICLOUD` capability, but no app record by exact bundle, expected SKU `captainslog-ios`, or expected name `Captain's Log`.
- Regenerate or download an active App Store provisioning profile for `com.blakecrosley.captainslog`, then prove one iOS export signing path: App Store Connect API-key auth for `xcodebuild` provisioning updates plus cloud-managed distribution certificate access, or the local Apple Distribution/iOS Distribution identity for team `M4WTLM6RAQ`.
- Regenerate the signed IPA and `ExportManifest.txt`.
- Reconcile the linked `../941Kit` package source before final export; the latest readiness run reports `Sources/Kit941/Resources/Localizable.xcstrings` is dirty after the previous IPA export.

Native Mac, Apple Watch, and Apple TV are separate platform gates. Mac and Apple TV now follow the single App Store record/universal-purchase bundle-ID model and share `com.blakecrosley.captainslog`; do not create separate `.mac` or `.tv` account state. Current REST evidence still reports the Captain's Log Watch companion bundle ID is missing or not visible. Native Mac App Store export additionally needs an active Mac App Store profile plus Mac installer signing proof, or the same App Store Connect API-key cloud signing path.

Current platform availability status:

- iPhone and iPad: locally prepared through the universal iOS app; not store-ready until a signed IPA is exported and uploaded.
- Apple Vision Pro: locally prepared through the compatible iPhone/iPad app path; not store-ready until signed upload, final smoke-test acceptance, and App Store Connect availability selection are complete. This is not a native visionOS app.
- Mac: a native macOS target exists, but do not submit or market it until Mac signing/export, TestFlight, and human QA are complete.
- Apple Watch and Apple TV: companion targets exist and share an aggregate snapshot data path based on WatchConnectivity plus iCloud key-value sync. Do not submit or market them until signed export, TestFlight, provisioning validation, and platform QA are complete.

For the current platform verdict and the Watch/TV path after the first submission, use `Docs/PlatformExpansionPlan.md`.

Refresh the local Vision compatible-app smoke before final Vision acceptance:

```sh
Scripts/smoke_vision_compatible_launch.sh /tmp/captainslog-vision-smoke
```

Refresh the local native Mac launch smoke before accepting Mac availability:

```sh
Scripts/smoke_macos_launch.sh /tmp/captainslog-macos-smoke
```

Refresh the local Watch/TV launch smokes before accepting the companion snapshot UI:

```sh
Scripts/smoke_watchos_launch.sh /tmp/captainslog-watchos-smoke
Scripts/smoke_tvos_launch.sh /tmp/captainslog-tvos-smoke
```

After active App Store provisioning profiles exist and either local distribution signing or API-key cloud signing is available:

```sh
Scripts/app_store_signing_status.sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_app_store_ipa.sh /tmp/captainslog-current-appstore-export
Scripts/app_store_readiness_status.sh
```

If intentionally adding the native Mac target to this release:

```sh
CAPTAINS_LOG_REQUIRE_CLEAN_EXPORT=1 Scripts/export_macos_app_store_pkg.sh /tmp/captainslog-current-macos-appstore-export
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
