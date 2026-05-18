# Captain's Log App Store Design Review

Review date: May 17, 2026

Follow-up screenshot spot-check: May 18, 2026

Artifacts reviewed:

- `/tmp/captainslog-appstore-review/review.html`
- `/tmp/captainslog-appstore-review/contact-sheet.png`
- `/tmp/captainslog-key-state-packaged/iphone-6.9`
- `/tmp/captainslog-key-state-packaged/ipad-13`

## Design Context

Captain's Log is for developers who want a quick, private way to understand what they shipped from GitHub history. The product should feel quiet, precise, and journal-like, closer to a trustworthy developer notebook than a generic analytics dashboard or gamified productivity tracker.

The Work Map / histogram should carry the identity. GitHub permissions and local/cloud data boundaries should be understandable without extra explanation.

## Design Verdict

Locally acceptable for the first App Store Connect screenshot pass, pending human approval.

The current set reads as one coherent progression:

1. Dashboard: daily overview, selected week, and Work Map.
2. Work Map: long-range memory surface.
3. Journal: readable daily note backed by commit evidence.
4. Repositories: GitHub access and repo selection.
5. AI providers: optional bring-your-own-key cloud providers.
6. Privacy & Data: local-first claims, support, and user controls.

The iPhone set is the stronger marketing set. It is compact, legible, and makes the product shape clear without marketing overlays.

The iPad set is acceptable for v1. Some screens intentionally preserve calm whitespace instead of filling the canvas with extra dashboard furniture. This is a reasonable tradeoff for a developer journal app, but it should still be checked by a person at App Store preview scale before upload.

The May 18 contact-sheet spot-check found that the iPad thumbnails make the lower whitespace look more severe than the full-size screenshots. The full-size iPad dashboard still reads as a complete adaptive layout, while the Work Map detail remains the main composition to approve or reject during the final human screenshot pass.

A later May 18 dashboard polish pass removed the second full-width segmented control from the selected-period card. The dashboard still supports Day, Week, Month, and Year, but the period choice now lives in a compact header menu so the first screen has one obvious global lens control and less visible decision clutter.

A later May 18 repository pass split the iPad repository access screen into a left control rail and right repository list. This keeps the long list scannable without leaving the selection summary, search, filter, and GitHub access actions floating above a mostly empty tablet page.

## May 18 Design-Skill Spot-Check

Reviewed against the local `.impeccable.md` direction and the `frontend-design`, `critique`, and `polish` skills:

- Cave availability: `$cave` was requested as the preferred design-review lens, but no Cave tool or connector is available in the current Codex tool registry. This review is therefore the local substitute, and human screenshot approval remains the final taste gate.
- Anti-pattern verdict: passes for v1. The packet no longer reads as neon/cyberpunk, AI-gradient, generic SaaS dashboard, or card-stack demo UI.
- Information hierarchy: acceptable. The iPhone dashboard starts with account, selected week, Work Map, and the selected-period metric; detail screens move evidence and settings into focused pages instead of flooding the dashboard.
- Progressive disclosure: acceptable. Dashboard, Work Map, journal, repository access, AI provider, and Privacy & Data screenshots each say one clear thing.
- Control weight: improved. The dashboard keeps `Changes / Commits` as the primary lens and moves period changes into a smaller local menu, while the Work detail sheet keeps the full segmented period control for deeper analysis.
- Remaining taste risk: iPad screenshots are calm and spacious. This is defensible for a developer journal, and the repository access split reduces one of the more obviously underused tablet compositions, but final App Store preview should still judge whether the whitespace feels intentional at actual upload scale.
- Recommendation: no more local UI work before first TestFlight unless human screenshot approval finds clipped text, exposed private data, confusing disabled controls, active sync progress, or an unfinished iPad composition.

## What Passes

- The screenshots do not present Captain's Log as a loud SaaS dashboard.
- The Work Map is visible early and clearly acts as the identity surface.
- The journal screenshot shows traceability from summary to commit evidence.
- Repository and Privacy & Data screenshots explain permissions and data handling.
- AI provider screenshots show cloud AI as optional and key-backed.
- The fixture identity is neutral and does not appear to expose a real private GitHub account.
- The latest regenerated review artifacts do not show visible sync bars, debug labels, previous-app breadcrumbs, or simulator chrome.
- A Vision OCR pass over the packaged screenshots found no `fixture`, `UI Fixture`, debug, simulator, sync-progress, error, personal-account, or token-like text. The journal screenshot now reads as a demo product story and labels the generated summary source as `Captain's Log`.

## Remaining Human Checks

Before uploading to App Store Connect, a person should still confirm:

- No screenshot reveals real private repository names, live API keys, personal email addresses, or personal GitHub data.
- Text remains legible at App Store preview scale on both iPhone and iPad.
- No visible control is clipped, overlapped, or disabled in a confusing way.
- The dashboard screenshot communicates the app in under five seconds.
- The iPad whitespace feels intentional rather than unfinished.
- The set still feels quiet, precise, and journal-like after viewing the actual App Store upload preview.

## Current Design Score

Score: 33 / 40

| Area | Score | Notes |
| --- | --- | --- |
| Product clarity | 4 / 4 | The screenshot sequence explains overview, history, journal, access, AI, and privacy. |
| Visual hierarchy | 3 / 4 | iPhone hierarchy is strong; iPad is calmer but sometimes spacious. |
| Cognitive load | 3 / 4 | Dashboard and detail split is much better than earlier dense versions. |
| Trust and privacy clarity | 4 / 4 | Privacy, local storage, GitHub access, and optional AI are visible. |
| App Store screenshot strength | 3 / 4 | Good v1 set; final marketing acceptance remains human. |
| Distinctiveness | 3 / 4 | Work Map gives identity without decorative chrome. |
| Platform fit | 4 / 4 | Apple-native surfaces and controls feel appropriate. |
| Polish risk | 3 / 4 | No obvious clipping in the reviewed artifacts; final device preview remains open. |
| Data story | 3 / 4 | The story is clear enough; real-account data plausibility is separately audited. |
| Restraint | 3 / 4 | The design stays calm; avoid adding more cards or dashboard modules before submission. |

## Recommendation

Do not add major new features before the first TestFlight/App Store Connect pass. The best next product work is external closeout:

1. App Store Connect app record.
2. App Store Connect API credentials.
3. Build validation and upload.
4. TestFlight processing.
5. Human screenshot approval using `/tmp/captainslog-appstore-review/review.html`.
6. Legal/privacy review.
7. Final real-account tap-through.

Only make UI changes before submission if the final human screenshot review finds clipped text, exposed private data, confusing disabled controls, or an obviously unfinished iPad composition.
