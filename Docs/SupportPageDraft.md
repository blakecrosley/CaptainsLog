# Captain's Log Support Page

Draft status: published at `https://blakecrosley.com/captains-log/support` with final contact information.

Captain's Log is a private GitHub work journal for iPhone and iPad.

## Contact

For app issues, feedback, feature requests, or privacy questions, contact:

```text
blake@941apps.com
```

App Store Connect requires the Support URL to lead to actual contact information.

## Common Questions

### Do I need a GitHub account?

Yes. Captain's Log reads repository and commit history from GitHub repositories you choose to make available to the app.

### Can I try the app without connecting GitHub?

Yes. The first-run screen includes demo data so you can preview the dashboard, work map, settings, privacy screen, and journal detail without external credentials.

### Where is my data stored?

Imported repository history, work metrics, generated journals, and app preferences are stored on your device. GitHub sessions and optional AI provider keys are stored in the device Keychain.

### What leaves my device?

Captain's Log sends requests to GitHub when you sign in, choose repositories, sync commits, or import diff stats.

Journal summaries use Apple Foundation Models on device when available. If you attach an OpenAI or Anthropic key and generate a journal entry, selected commit evidence is sent directly to the provider you selected for that request.

During GitHub sign-in, tapping "Copy & Open GitHub" copies the short-lived device code to the system pasteboard. Captain's Log does not read from the pasteboard.

### How do I disconnect GitHub?

Open Settings in Captain's Log and sign out of GitHub. You can also revoke or change repository access from your GitHub App installation settings.

### How do I delete local imported history?

Open Settings > Privacy & Data > Clear Imported History. This removes imported commits, line stats, and generated journals from this device.

### How do I remove an AI key?

Open Settings > AI providers, choose the provider, and delete the attached key.

## Useful Links

- Privacy Policy: `https://blakecrosley.com/captains-log/privacy`
- GitHub App access: `https://github.com/settings/installations`
