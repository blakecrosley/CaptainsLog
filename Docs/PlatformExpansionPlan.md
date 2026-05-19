# Captain's Log Platform Expansion Plan

This plan turns the current platform-readiness answer into implementation gates. Do not count a platform as ready because another 941 app already has that platform; Return and Get Bananas are references, not substitute evidence for Captain's Log.

## Current Verdict

- iPhone and iPad: the universal iOS app is the first release path. Local readiness supports iPad through target family `1,2`, but signed IPA export and upload remain open.
- Apple Vision Pro: use the compatible iPhone/iPad app availability path after final smoke-test acceptance. This is not a native visionOS target.
- Mac: a native macOS target exists, but Mac App Store availability remains blocked on native Mac bundle/app-record visibility, Mac App Store signing/export, TestFlight, screenshot acceptance, and human QA.
- Apple Watch: first-pass companion target exists and compiles with signing disabled, but it is not ready. The missing gates are phone-synced data, icons, screenshots, signed build/export, TestFlight, app record/platform availability, and watch-specific QA.
- Apple TV: first-pass read-only target exists and compiles with signing disabled, but it is not ready. The missing gates are real setup/data path, icons/top-shelf assets, screenshots, signed build/export, TestFlight, app record/platform availability, and TV-specific QA.

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

- Today summary: commits, changed lines, top repo, and latest journal headline.
- Week strip: compact activity map for the current week.
- Sync state: last phone sync time and a clear empty state when no phone snapshot exists.
- Deep link or handoff affordance back to iPhone for GitHub auth, repo selection, AI provider keys, and long-form journal review.

Implementation gates:

- Add a watchOS app target, scheme, bundle ID, icons, privacy manifest, and entitlements. The target, scheme, bundle ID, and privacy manifest now exist; icons/entitlements still need release review.
- Add a small shared snapshot model that can be produced by the iOS app without exposing tokens or provider keys.
- Use WatchConnectivity or an equivalent local Apple framework for iPhone-to-watch snapshot transfer.
- Add watch screenshots, at least one watch UI test or launch smoke, and a TestFlight pass before claiming readiness.

## TV V1

Build a remote-friendly read-only dashboard. Apple TV should make the Work Map useful on a larger shared screen:

- GitHub Device Flow sign-in or iPhone-assisted setup, with no keyboard-heavy path.
- Work Map, current week summary, recent journals, and repository highlights.
- Focus-safe navigation using large targets, clear selection states, and Kit941 tvOS focus styling where appropriate.
- No editing, AI key management, or dense repository administration in the first TV slice.

Implementation gates:

- Add a tvOS app target, scheme, bundle ID, icons/top-shelf assets, privacy manifest, and entitlements. The target, scheme, bundle ID, and privacy manifest now exist; icons/top-shelf assets and entitlements still need release review.
- Prove GitHub auth or iPhone-assisted setup on tvOS.
- Add tvOS screenshots, a focus/navigation smoke, and a TestFlight pass before claiming readiness.

## Sequence

1. Finish the universal iOS/iPad plus compatible Vision submission path by unblocking App Store signing, regenerating the signed IPA/export manifest, and completing App Store Connect/TestFlight.
2. Decide whether native Mac belongs in the first release. If yes, complete Mac signing/export/TestFlight/QA; otherwise opt out of Apple Silicon Mac availability for this submission.
3. Replace the Watch shell with Watch V1 as a phone-synced companion snapshot.
4. Replace the TV shell with TV V1 as a remote-friendly read-only dashboard.
5. Only update App Store availability once the platform's own readiness standard above is met.
