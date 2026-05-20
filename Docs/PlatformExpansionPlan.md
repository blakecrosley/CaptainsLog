# Captain's Log Platform Expansion Plan

This plan turns the current platform-readiness answer into implementation gates. Do not count a platform as ready because another 941 app already has that platform; Return and Get Bananas are references, not substitute evidence for Captain's Log.

## Current Verdict

- iPhone and iPad: the universal iOS app is the first release path. Local readiness supports iPad through target family `1,2`, but signed IPA export and upload remain open.
- Apple Vision Pro: use the compatible iPhone/iPad app availability path after final smoke-test acceptance. This is not a native visionOS target.
- Mac: a native macOS target exists and now shares the iOS app bundle ID `com.blakecrosley.captainslog` for the single App Store record/universal-purchase path. Mac App Store availability remains blocked on signing/export, TestFlight, store-media acceptance, and human QA.
- Apple Watch: companion target exists, compiles/launches with signing disabled, has a phone-synced aggregate snapshot path, and has an AppIcon asset. It is not ready until signed build/export, TestFlight, App Store platform availability, paired-device QA, provisioning validation, and store-media acceptance are complete.
- Apple TV: read-only companion target exists, now shares the iOS app bundle ID `com.blakecrosley.captainslog`, compiles/launches with signing disabled, reads the same aggregate snapshot through iCloud key-value sync, and has app icon/top-shelf assets. It is not ready until signed build/export, TestFlight, App Store platform availability, TV QA, provisioning validation, and store-media acceptance are complete.

Current May 20, 2026 account/signing audit:

- `CAPTAINS_LOG_SKIP_MEDIA_CHECKS=1 Scripts/app_store_readiness_status.sh` still fails local readiness because the current iOS IPA and export manifest are missing. CaptainsLog is clean but ahead of `origin/main`, and linked `../941Kit` is clean but ahead of `origin/main` by 1 commit at `fe4bfd3 Add Kit941 localization catalog entries`; push or explicitly accept both unpushed save points before final release export.
- `Scripts/check_remote_signing_assets.py --require` reports 2 usable / 2 visible iOS App Store distribution certificates, 2 usable / 2 visible Mac App Store application certificates through Apple Distribution, 0 usable visible Mac installer certificates, an invalid visible `IOS_APP_STORE` profile for `com.blakecrosley.captainslog`, no required active iOS/Mac/tvOS App Store profiles, and the Watch companion bundle ID missing.
- `Scripts/check_app_store_connect_record.py` evidence in the submission packet shows the Developer Portal bundle ID exists and `ICLOUD` is enabled for `com.blakecrosley.captainslog`, but no App Store Connect app record is visible by exact bundle relationship, expected SKU `captainslog-ios`, or expected name `Captain's Log`.
- The Watch bundle-ID helper is dry-run safe by default. It plans only `com.blakecrosley.captainslog.watchkitapp` plus `ICLOUD`; do not run `--apply` without explicit Apple account mutation approval.

## Prompt-To-Artifact Checklist

| User ask | Captain's Log evidence | Current answer | Next blocking action |
| --- | --- | --- | --- |
| "does this app have an iPad version ready?" | `project.yml` sets the iOS target to `TARGETED_DEVICE_FAMILY: "1,2"`; readiness reports iPhone/iPad enabled. | Locally yes, store no. It ships through the universal iOS app after signed IPA export and App Store Connect upload. | Create the App Store Connect app record, make distribution signing work, reconcile linked Kit941 source, regenerate the signed IPA/export manifest, then upload/TestFlight. |
| "does this app have a mac version ready?" | `CaptainsLog-macOS` exists with shared bundle ID `com.blakecrosley.captainslog`, automatic signing team `M4WTLM6RAQ`, and local smoke evidence. A current May 19, 2026 no-sign Release build succeeded at `/tmp/captainslog-current-macos-release-kit941-fe4bfd3` with bundle ID `com.blakecrosley.captainslog`, version `1.0.0 (1)`, and privacy manifest present. Apple says added Mac platform versions in a single app record/universal purchase share the iOS app bundle ID; Get Bananas uses that main-bundle-ID pattern. Current remote signing evidence has Mac App Store application signing visible through Apple Distribution, but still lacks a usable Mac installer certificate and active `MAC_APP_STORE` profile. | Target exists, not Mac App Store ready. | Produce a signed Mac App Store package and `MacExportManifest.txt`, then complete TestFlight, store-media acceptance, and QA. |
| "does this app have an Apple Watch version ready?" | `CaptainsLog-watchOS` exists with bundle ID `com.blakecrosley.captainslog.watchkitapp`, unsigned local launch evidence, and a phone-synced aggregate snapshot path. A current May 19, 2026 no-sign Release build succeeded at `/tmp/captainslog-current-watchos-release-kit941-fe4bfd3` with version `1.0.0 (1)` and privacy manifest present. A no-screenshot simulator smoke installed and launched process `33299`. REST checks report the Watch Developer Portal bundle ID is missing. | Companion exists locally, not App Store ready. | After explicit account-mutation approval, create the Watch bundle ID/capabilities, regenerate profiles, prove signed archive/export, TestFlight, paired-device QA, and store-media acceptance. |
| "does this app have an Apple TV version ready?" | `CaptainsLog-tvOS` exists with shared bundle ID `com.blakecrosley.captainslog`, unsigned local launch evidence, top-shelf assets, and an iCloud read-only snapshot path. A current May 19, 2026 no-sign Release build succeeded at `/tmp/captainslog-current-tvos-release-kit941-fe4bfd3` with version `1.0.0 (1)` and privacy manifest present. A no-screenshot simulator smoke installed and launched process `34260`. Return's tvOS target uses the same bundle ID as its iOS app. Current remote signing evidence has the required iOS distribution certificate visible, but still lacks an active `TVOS_APP_STORE` profile. | Target exists locally, not App Store ready. | Regenerate the required TV App Store signing/profile path, prove signed archive/export, TestFlight, living-room QA, and store-media acceptance. |
| "put it in the vision store too" | The iOS target supports compatible Vision availability; the no-screenshot Vision smoke builds, installs, and launches the compatible app on a Vision simulator. The latest run recorded process `40063` with `screenshot=skipped`. | Use compatible iPhone/iPad availability, not native visionOS. Store readiness still depends on signed iOS upload and App Store Connect availability selection. | After signed iOS upload, select compatible Apple Vision Pro availability in App Store Connect and complete human acceptance. |
| "we have all that in other apps, like Return, Get Bananas" | ReturnTV uses `com.941apps.Return`, matching Return's iOS bundle ID; Return Watch uses `com.941apps.Return.watchkitapp`; Get Bananas uses `com.941apps.Banana-List` for its main iOS/Mac app and `com.941apps.Banana-List.watchkitapp` for Watch. | Useful precedent, but not a substitute for Captain's Log evidence. Captain's Log now follows that bundle-ID model for Mac/TV and Watch. | Use `Scripts/ensure_platform_bundle_ids.py --target watchos --apply --confirm-team M4WTLM6RAQ` only after Apple account mutation approval for the Watch companion; Mac/TV use the iOS app record bundle ID. |

## Readiness Standard

A platform is ready only when all of these are true for Captain's Log itself:

- `project.yml` defines the app target and generated Xcode schemes include it.
- The platform has the correct bundle ID model for its distribution path, App Store Connect record or platform version, icons, privacy manifest, entitlements, screenshots, and metadata.
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
- Add store media and a TestFlight pass before claiming readiness. Local media automation can help later, but TestFlight and paired-device validation are the release authority.

## TV V1

Build a remote-friendly read-only dashboard. Apple TV should make the Work Map useful on a larger shared screen:

- iPhone/iPad/Mac-assisted setup, with no GitHub credentials entered on the shared screen.
- Current day, current week, journal availability, and selected repository counts from the aggregate companion snapshot.
- Focus-safe navigation using large targets, clear selection states, and Kit941 tvOS focus styling where appropriate.
- No editing, AI key management, or dense repository administration in the first TV slice.

Implementation gates:

- Add a tvOS app target, scheme, bundle ID, icons/top-shelf assets, privacy manifest, and entitlements. The target, scheme, bundle ID, privacy manifest, iCloud key-value entitlements, App Icon & Top Shelf Image brand assets, and local App Store screenshot capture now exist; signed provisioning still needs release review.
- Prove the iCloud key-value snapshot path under signed provisioning and TestFlight.
- Add tvOS store media and a TestFlight pass before claiming readiness. Local media automation can help later, but TestFlight and living-room QA are the release authority.

## Sequence

1. Finish the universal iOS/iPad plus compatible Vision submission path by unblocking App Store signing, regenerating the signed IPA/export manifest, and completing App Store Connect/TestFlight.
2. Decide whether native Mac belongs in the first release. If yes, complete Mac signing/export/TestFlight/QA; otherwise opt out of Apple Silicon Mac availability for this submission.
3. Finish Watch V1 by validating the phone-synced companion snapshot under signed provisioning, TestFlight, paired-device QA, and store-media acceptance.
4. Finish TV V1 by validating the iCloud read-only dashboard under signed provisioning, TestFlight, living-room QA, and store-media acceptance.
5. Only update App Store availability once the platform's own readiness standard above is met.
