# Captain's Log

Captain's Log is an iPhone and iPad app for turning GitHub history into a private work journal. It connects to GitHub, imports selected repository history, shows a Work Map of commits or changed lines, and generates daily notes from the work evidence.

## App Store Connect Status

Start with the current gate:

```sh
Scripts/app_store_readiness_status.sh
```

As of the current App Store packet, the local metadata, privacy manifest, screenshot package, design review, and helper scripts are ready for handoff, but the App Store build is still blocked until one signing path is available:

- App Store Connect API-key auth for `xcodebuild` provisioning updates, or
- an Apple Distribution/iOS Distribution signing identity for team `M4WTLM6RAQ`.

Native Mac App Store export additionally needs Mac App Store application and installer signing, or the same App Store Connect API-key auth path.

Current platform availability status:

- iPhone and iPad: ready as the universal iOS app once a signed IPA is exported and uploaded.
- Apple Vision Pro: use the compatible iPhone/iPad app path after final smoke-test acceptance; this is not a native visionOS app.
- Mac: a native macOS target exists and local Mac screenshot candidates can be generated, but do not submit it until Mac signing/export, TestFlight, screenshot acceptance, and human QA are complete.
- Apple Watch and Apple TV: first-pass companion targets now build and launch in simulator smoke scripts, but do not submit them until data sync/setup, platform assets, screenshots, signed export, TestFlight, and human QA are complete.

For the Watch/TV path after the first submission, use `Docs/PlatformExpansionPlan.md`.

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

Refresh the local Watch/TV launch smokes before accepting those targets as more than shells:

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
