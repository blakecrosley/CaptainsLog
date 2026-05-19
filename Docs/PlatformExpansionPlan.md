# Captain's Log Platform Expansion Plan

This plan turns the current platform-readiness answer into implementation gates. Do not count a platform as ready because another 941 app already has that platform; Return and Get Bananas are references, not substitute evidence for Captain's Log.

## Current Verdict

- iPhone and iPad: the universal iOS app is the first release path. Local readiness supports iPad through target family `1,2`, but signed IPA export and upload remain open.
- Apple Vision Pro: use the compatible iPhone/iPad app availability path after final smoke-test acceptance. This is not a native visionOS target.
- Mac: a native macOS target exists, but Mac App Store availability remains blocked on native Mac bundle/app-record visibility, Mac App Store signing/export, TestFlight, screenshot acceptance, and human QA.
- Apple Watch: companion target exists, compiles/launches with signing disabled, has a phone-synced aggregate snapshot path, has an AppIcon asset, and has a local App Store screenshot capture. It is not ready until signed build/export, TestFlight, App Store platform availability, paired-device QA, provisioning validation, and human screenshot acceptance are complete.
- Apple TV: read-only companion target exists, compiles/launches with signing disabled, reads the same aggregate snapshot through iCloud key-value sync, has app icon/top-shelf assets, and has a local App Store screenshot capture. It is not ready until signed build/export, TestFlight, App Store platform availability, TV QA, provisioning validation, and human screenshot acceptance are complete.

## Readiness Standard

A platform is ready only when all of these are true for Captain's Log itself:

- `project.yml` defines the app target and generated Xcode schemes include it.
- The platform has its own bundle ID, App Store Connect record or platform version, icons, privacy manifest, entitlements, screenshots, and metadata.
- The app has a product-worthy user path designed for the device, not a placeholder shell.
- Release or App Store configuration builds succeed for the platform.
- A simulator or device smoke path proves launch and the primary user path.
- TestFlight or equivalent App Store Connect processing is complete.
- Human QA accepts the platform on real or representative hardware.

## References

- Return provides working watchOS and tvOS precedents: `ReturnWatch Watch App` and `ReturnTV`, with platform-specific source trees, assets, entitlements, UI tests, and screenshots.
- Get Bananas provides a watchOS companion precedent through `Banana List Watch Watch App`, including WatchConnectivity-style sync/shared types for phone-to-watch data.
- Kit941 now includes reusable tvOS-focused button styling, but library support is not a Captain's Log tvOS app.

## Watch V1

Build a companion glance, not a second GitHub client. The watch app should mirror a compact snapshot from the iPhone app:

- Today summary: commits or changed lines, journal availability, and selected repository counts without exposing private repository names or commit text.
- Week strip: compact activity map for the current week.
- Sync state: last snapshot time and a clear empty state when no phone snapshot exists.
- Deep link or handoff affordance back to iPhone for GitHub auth, repo selection, AI provider keys, and long-form journal review.

Implementation gates:

- Add a watchOS app target, scheme, bundle ID, icons, privacy manifest, and entitlements. The target, scheme, bundle ID, privacy manifest, iCloud key-value entitlements, and AppIcon asset now exist; signed provisioning still needs release review.
- Add a small shared snapshot model that can be produced by the main app without exposing tokens, provider keys, repository names, commit messages, file paths, or journal text. This aggregate snapshot now exists in `CaptainsLogShared`.
- Use WatchConnectivity or an equivalent local Apple framework for iPhone-to-watch snapshot transfer. The current Watch path requests the latest snapshot from the phone and accepts pushed application-context snapshots.
- Add watch screenshots and a TestFlight pass before claiming readiness. `Scripts/capture_watchos_app_store_screenshots.sh` now wraps the unsigned simulator launch/screenshot/OCR smoke and stages a local App Store-sized screenshot; TestFlight and paired-device validation remain open.

## TV V1

Build a remote-friendly read-only dashboard. Apple TV should make the Work Map useful on a larger shared screen:

- iPhone/iPad/Mac-assisted setup, with no GitHub credentials entered on the shared screen.
- Current day, current week, journal availability, and selected repository counts from the aggregate companion snapshot.
- Focus-safe navigation using large targets, clear selection states, and Kit941 tvOS focus styling where appropriate.
- No editing, AI key management, or dense repository administration in the first TV slice.

Implementation gates:

- Add a tvOS app target, scheme, bundle ID, icons/top-shelf assets, privacy manifest, and entitlements. The target, scheme, bundle ID, privacy manifest, iCloud key-value entitlements, App Icon & Top Shelf Image brand assets, and local App Store screenshot capture now exist; signed provisioning still needs release review.
- Prove the iCloud key-value snapshot path under signed provisioning and TestFlight.
- Add tvOS screenshots and a TestFlight pass before claiming readiness. `Scripts/capture_tvos_app_store_screenshots.sh` now wraps the unsigned simulator launch/screenshot/OCR smoke and stages a local App Store-sized screenshot; TestFlight and living-room QA remain open.

## Sequence

1. Finish the universal iOS/iPad plus compatible Vision submission path by unblocking App Store signing, regenerating the signed IPA/export manifest, and completing App Store Connect/TestFlight.
2. Decide whether native Mac belongs in the first release. If yes, complete Mac signing/export/TestFlight/QA; otherwise opt out of Apple Silicon Mac availability for this submission.
3. Finish Watch V1 by validating the phone-synced companion snapshot under signed provisioning, TestFlight, paired-device QA, and human screenshot acceptance.
4. Finish TV V1 by validating the iCloud read-only dashboard under signed provisioning, TestFlight, living-room QA, and human screenshot acceptance.
5. Only update App Store availability once the platform's own readiness standard above is met.
