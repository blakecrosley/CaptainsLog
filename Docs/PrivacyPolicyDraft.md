# Captain's Log Privacy Policy

Draft status: published at `https://blakecrosley.com/captains-log/privacy` with final contact information. Legal review is still recommended before App Store Connect submission.

Effective date: May 17, 2026

Captain's Log helps developers understand their GitHub work history. This policy explains what data the app uses, where it is stored, and what leaves the device.

## Data the App Uses

When you connect GitHub, Captain's Log requests information needed to show your work history:

- GitHub account identity, such as your login and avatar.
- Repository metadata for repositories you choose to make available to the app.
- Commit metadata, commit messages, authorship information, changed files, and diff statistics for selected repositories.
- Generated journal summaries and work classifications created from that commit history.

Captain's Log does not ask for contacts, photos, location, health, fitness, microphone, camera, advertising identifier, or payment data.

## Where Data Is Stored

Captain's Log stores imported repository history, work metrics, generated journals, and app preferences on your device.

GitHub sessions and optional AI provider keys are stored in the device Keychain. API keys are not stored in Captain's Log servers.

## GitHub

Captain's Log uses GitHub sign-in so you can access your own repository content. GitHub access is limited by the repositories you select through GitHub App installation settings.

You can disconnect GitHub in the app. You can also revoke or change repository access from GitHub.

## AI Summaries

Captain's Log can generate journal summaries from selected commit evidence.

When Apple Foundation Models are available, summaries can be generated on device.

If you attach an OpenAI or Anthropic API key, Captain's Log sends selected commit evidence directly to the selected provider only when you generate a journal entry. This may include repository names, commit messages, changed file paths, and diff summaries needed to create the journal. Provider keys are stored in Keychain and can be deleted from AI settings.

Do not attach a cloud AI key if you do not want selected commit evidence sent to that provider.

## Analytics, Advertising, and Tracking

The current app does not include advertising SDKs, tracking SDKs, or product analytics SDKs.

Captain's Log does not use your data for third-party advertising or tracking.

## Data Retention and Deletion

Local app data remains on your device until you delete the app, remove data through system storage controls, or use Privacy & Data > Clear Imported History to remove imported commits, line stats, and generated journals from this device.

GitHub access can be revoked from GitHub or disconnected in the app. AI provider keys can be removed from AI settings.

## Third-Party Services

Captain's Log can communicate with these services for app functionality:

- GitHub, for sign-in, repository access, commit history, and diff stats.
- OpenAI, only when you attach an OpenAI key and generate cloud AI output.
- Anthropic, only when you attach an Anthropic key and generate cloud AI output.

Each third-party service processes requests under its own terms and privacy practices.

## International Transfers

GitHub, OpenAI, and Anthropic may process requests outside your country or region. Captain's Log does not control where those services process data.

## Children's Privacy

Captain's Log is a developer tool and is not directed to children.

## Contact

For privacy or support questions, contact:

```text
blake@941apps.com
```

## Changes

This policy may be updated as Captain's Log changes. The effective date above will be updated when the policy changes.
