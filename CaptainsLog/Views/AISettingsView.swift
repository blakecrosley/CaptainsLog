import SwiftUI
import Kit941

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var credentialRevision: Int
    @AppStorage(AIProviderCredentialStore.preferredProviderDefaultsKey) private var preferredProviderRaw = AIProvider.openai.rawValue

    @State private var selectedProvider = AIProvider.openai
    @State private var key = ""
    @State private var storedKeyPreviews: [AIProvider: String] = [:]
    @State private var message: String?
    @State private var messageIsError = false
    @State private var isTesting = false
    @State private var isConfirmingDelete = false

    private let store = AIProviderCredentialStore.shared

    private var hasKey: Bool {
        storedKeyPreviews[selectedProvider] != nil
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                header
                providerCard
                keyCard
                note
            }
            .padding(.horizontal, Kit941.Spacing.md)
            .padding(.vertical, Kit941.Spacing.lg)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppSurface.backgroundGradient.ignoresSafeArea())
        .navigationTitle("AI")
        .confirmationDialog("Remove \(selectedProvider.displayName) key?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Key", role: .destructive) {
                delete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Captain's Log will stop using \(selectedProvider.displayName) until a new key is attached.")
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            selectedProvider = AIProvider(rawValue: preferredProviderRaw) ?? .openai
            refreshStoredKeyState()
        }
        .onChange(of: selectedProvider) { _, provider in
            preferredProviderRaw = provider.rawValue
            key = ""
            message = nil
            credentialRevision += 1
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            Text("AI providers")
                .kit941Font(.display, weight: .bold)
            Text("Use Apple on-device by default. Attach OpenAI or Anthropic only when you want cloud-generated journals.")
                .kit941Font(.body)
                .foregroundStyle(AppSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var providerCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                VStack(alignment: .leading, spacing: Kit941.Spacing.xs) {
                    Text("Current provider")
                        .kit941Font(.title, weight: .semibold)
                    Text("Choose the cloud model used for generated journals.")
                        .kit941Font(.caption)
                        .foregroundStyle(AppSurface.secondaryText)
                }

                Picker("Current provider", selection: $selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 0) {
                    ForEach(AIProvider.allCases) { provider in
                        providerStatusRow(provider)
                        if provider.id != AIProvider.allCases.last?.id {
                            Divider()
                        }
                    }
                }
                .background(AppSurface.mutedFill(opacity: 0.55), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
            }
        }
    }

    private var keyCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(spacing: Kit941.Spacing.sm) {
                    Image(systemName: hasKey ? "key.fill" : "key")
                        .foregroundStyle(hasKey ? AppSurface.accent : AppSurface.tertiaryText)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(selectedProvider.displayName) key")
                            .kit941Font(.title, weight: .semibold)
                        Text(hasKey ? "Key attached to this device" : "No key attached")
                            .kit941Font(.caption)
                            .foregroundStyle(AppSurface.secondaryText)
                    }
                    Spacer(minLength: 0)
                }

                if let preview = storedKeyPreviews[selectedProvider] {
                    attachedKeyRow(preview: preview)
                }

                SecureField(hasKey ? "Paste replacement key" : "Paste API key", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .privacySensitive()
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppSurface.mutedFill(opacity: 1), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))

                if let message {
                    Label(message, systemImage: messageIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .kit941Font(.caption)
                        .foregroundStyle(messageIsError ? AppSurface.warning : AppSurface.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
                    if !trimmedKey.isEmpty {
                        AppActionRow(
                            title: hasKey ? "Replace Key" : "Save Key",
                            description: "Store this \(selectedProvider.displayName) key in this device's Keychain.",
                            systemImage: "square.and.arrow.down",
                            isProminent: true,
                            showsChevron: false,
                            action: save
                        )
                    }

                    AppActionRow(
                        title: isTesting ? "Testing Connection" : "Test Connection",
                        description: "Verify the attached or pasted \(selectedProvider.displayName) key before using it for journals.",
                        systemImage: "checkmark.circle",
                        isDisabled: (trimmedKey.isEmpty && !hasKey) || isTesting,
                        showsChevron: false,
                        action: {
                            Task { await test() }
                        }
                    )
                }
            }
        }
    }

    private func providerStatusRow(_ provider: AIProvider) -> some View {
        Button {
            selectedProvider = provider
        } label: {
            HStack(spacing: Kit941.Spacing.sm) {
                Image(systemName: provider == selectedProvider ? "checkmark.circle.fill" : provider.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(provider == selectedProvider ? AppSurface.accent : AppSurface.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .kit941Font(.label, weight: .semibold)
                        .foregroundStyle(AppSurface.primaryText)
                    Text(storedKeyPreviews[provider] ?? "No key attached")
                        .font(.system(size: 12, weight: .medium, design: storedKeyPreviews[provider] == nil ? .default : .monospaced))
                        .foregroundStyle(AppSurface.secondaryText)
                        .privacySensitive(storedKeyPreviews[provider] != nil)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func attachedKeyRow(preview: String) -> some View {
        HStack(spacing: Kit941.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppSurface.accent)
                .frame(width: 38, height: 38)
                .background(AppSurface.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Key attached")
                    .kit941Font(.label, weight: .semibold)
                Text(preview)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppSurface.secondaryText)
                    .privacySensitive()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            Button {
                isConfirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppSurface.warning)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(selectedProvider.displayName) key")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .background(AppSurface.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
    }

    private var note: some View {
        Text("Keys are stored in this device's Keychain. Captain's Log sends summary requests directly to the selected provider only when you generate a journal entry.")
            .kit941Font(.caption)
            .foregroundStyle(AppSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func checkFormat(for candidate: String) {
        if let violation = selectedProvider.formatViolation(for: candidate) {
            message = violation
            messageIsError = true
        } else {
            message = "Key format looks valid."
            messageIsError = false
        }
    }

    private func test() async {
        guard let candidate = keyForTesting() else {
            message = "Paste or attach a \(selectedProvider.displayName) key first."
            messageIsError = true
            return
        }

        checkFormat(for: candidate)
        guard !messageIsError else {
            return
        }

        isTesting = true
        let result: Result<Void, Error>
        switch selectedProvider {
        case .openai:
            result = await OpenAIWorkClassifier().testConnection(key: candidate).mapError { $0 as Error }
        case .anthropic:
            result = await AnthropicJournalSummarizer().testConnection(key: candidate).mapError { $0 as Error }
        }
        isTesting = false

        switch result {
        case .success:
            message = trimmedKey.isEmpty ? "Attached key works." : "\(selectedProvider.displayName) connection works. Save to attach it."
            messageIsError = false
        case .failure(let error):
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func save() {
        if let violation = selectedProvider.formatViolation(for: trimmedKey) {
            message = violation
            messageIsError = true
            return
        }

        guard store.saveKey(trimmedKey, for: selectedProvider) else {
            message = "Keychain could not save this key."
            messageIsError = true
            return
        }

        key = ""
        refreshStoredKeyState()
        credentialRevision += 1
        message = "\(selectedProvider.displayName) key attached."
        messageIsError = false
    }

    private func delete() {
        store.deleteKey(for: selectedProvider)
        key = ""
        refreshStoredKeyState()
        credentialRevision += 1
        message = "\(selectedProvider.displayName) key deleted."
        messageIsError = false
    }

    private func refreshStoredKeyState() {
        storedKeyPreviews = AIProvider.allCases.reduce(into: [:]) { previews, provider in
            previews[provider] = store.keyPreview(for: provider)
        }
    }

    private func keyForTesting() -> String? {
        if !trimmedKey.isEmpty {
            return trimmedKey
        }
        return store.loadKey(for: selectedProvider)
    }
}
