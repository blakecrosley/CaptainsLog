# Captain's Log

Captain's Log is an iPhone and iPad app for turning GitHub history into a private work journal. It connects to GitHub, imports selected repository history, shows a Work Map of commits or changed lines, and generates daily notes from the work evidence.

## App Store Connect Status

Start with the current gate:

```sh
Scripts/app_store_readiness_status.sh
```

As of the current App Store packet, the local metadata, privacy manifest, screenshot package, design review, and helper scripts are ready for handoff, but the App Store path is still blocked until these external gates are closed:

- Create or make visible the App Store Connect app record for `com.blakecrosley.captainslog`; current REST evidence finds the Developer Portal bundle ID and required `ICLOUD` capability, but no app record by exact bundle, expected SKU `captainslog-ios`, or expected name `Captain's Log`.
- Make one iOS export signing path available: App Store Connect API-key auth for `xcodebuild` provisioning updates plus cloud-managed distribution certificate access, or an Apple Distribution/iOS Distribution signing identity for team `M4WTLM6RAQ`.
- Regenerate the signed IPA and `ExportManifest.txt`.

Native Mac, Apple Watch, and Apple TV are separate platform gates. Mac and Apple TV now follow the single App Store record/universal-purchase bundle-ID model and share `com.blakecrosley.captainslog`; do not create separate `.mac` or `.tv` account state. Current REST evidence still reports the Captain's Log Watch companion bundle ID is missing or not visible. Native Mac App Store export additionally needs Mac App Store application and installer signing, or the same App Store Connect API-key auth path.

Current platform availability status:

- iPhone and iPad: locally prepared through the universal iOS app; not store-ready until a signed IPA is exported and uploaded.
- Apple Vision Pro: locally prepared through the compatible iPhone/iPad app path; not store-ready until signed upload, final smoke-test acceptance, and App Store Connect availability selection are complete. This is not a native visionOS app.
- Mac: a native macOS target exists and local Mac screenshot candidates can be generated, but do not submit it until Mac signing/export, TestFlight, screenshot acceptance, and human QA are complete.
- Apple Watch and Apple TV: companion targets now build, launch, have platform icon/top-shelf assets, have local App Store screenshot captures, and share an aggregate snapshot data path based on WatchConnectivity plus iCloud key-value sync. Do not submit them until signed export, TestFlight, provisioning validation, human screenshot acceptance, and platform QA are complete.

For the current platform verdict and the Watch/TV path after the first submission, use `Docs/PlatformExpansionPlan.md`.

Refresh the local Vision compatible-app smoke before final Vision acceptance:

```sh
Scripts/smoke_vision_compatible_launch.sh /tmp/captainslog-vision-smoke
```

Refresh the local native Mac launch smoke before accepting Mac availability:

```sh
Scripts/smoke_macos_launch.sh /tmp/captainslog-macos-smoke
```

Refresh the local Mac screenshot candidates before Mac screenshot acceptance:

```sh
Scripts/capture_macos_app_store_screenshots.sh /tmp/captainslog-macos-appstore-screenshots
```

Refresh the local Watch/TV launch smokes before accepting the companion snapshot UI:

```sh
Scripts/smoke_watchos_launch.sh /tmp/captainslog-watchos-smoke
Scripts/smoke_tvos_launch.sh /tmp/captainslog-tvos-smoke
```

After distribution signing or API-key cloud certificate access is available:

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
- Privacy answers: `Docs/AppStorePrivacyAnswers.md`
- Design review: `Docs/AppStoreDesignReview.md`

Review the screenshot packet before upload:

```sh
Scripts/open_app_store_screenshot_review.sh
```

```text
/tmp/captainslog-appstore-review/review.html
/tmp/captainslog-appstore-review/contact-sheet.png
```

Do not commit App Store Connect contact details, demo credentials, API key IDs, issuer IDs, provider IDs, `.p8` private keys, provisioning profiles, certificates, exported IPAs, or archives.
