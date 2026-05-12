import SwiftUI
import Kit941

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var credentialRevision: Int

    @State private var key = ""
    @State private var storedKeyPreview = AIProviderCredentialStore.shared.keyPreview(for: .openai)
    @State private var message: String?
    @State private var messageIsError = false
    @State private var isTesting = false
    @State private var isConfirmingDelete = false

    private let store = AIProviderCredentialStore.shared

    private var hasKey: Bool {
        storedKeyPreview != nil
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Kit941.Spacing.lg) {
                    header
                    keyCard
                    note
                }
                .padding(.horizontal, Kit941.Spacing.md)
                .padding(.vertical, Kit941.Spacing.lg)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppSurface.background.ignoresSafeArea())
            .navigationTitle("AI")
            .confirmationDialog("Remove OpenAI key?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Key", role: .destructive) {
                    delete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Captain's Log will stop using OpenAI until a new key is attached.")
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
                refreshStoredKeyState()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Kit941.Spacing.sm) {
            Text("OpenAI BYOK")
                .kit941Font(.display, weight: .bold)
            Text("When a key is attached, Captain's Log uses OpenAI for journal generation. Without a key, it uses Apple Foundation Models.")
                .kit941Font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keyCard: some View {
        Kit941.Card {
            VStack(alignment: .leading, spacing: Kit941.Spacing.md) {
                HStack(spacing: Kit941.Spacing.sm) {
                    Image(systemName: hasKey ? "key.fill" : "key")
                        .foregroundStyle(hasKey ? AppSurface.accent : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OpenAI key")
                            .kit941Font(.title, weight: .semibold)
                        Text(hasKey ? "Key attached to this device" : "No key attached")
                            .kit941Font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                if let storedKeyPreview {
                    attachedKeyRow(preview: storedKeyPreview)
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
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))

                if let message {
                    Label(message, systemImage: messageIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .kit941Font(.caption)
                        .foregroundStyle(messageIsError ? Kit941.Status.warning : Kit941.Status.success)
                }

                HStack(spacing: Kit941.Spacing.sm) {
                    Kit941.Button {
                        await test()
                    } label: {
                        Label(isTesting ? "Testing" : "Test", systemImage: "checkmark.circle")
                    }
                    .disabled((trimmedKey.isEmpty && !hasKey) || isTesting)

                    Kit941.Button(role: .secondary) {
                        await MainActor.run { save() }
                    } label: {
                        Label(hasKey ? "Replace" : "Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(trimmedKey.isEmpty)
                }
            }
        }
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
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(Kit941.Status.warning)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete OpenAI key")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .background(AppSurface.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Kit941.Radius.md, style: .continuous))
    }

    private var note: some View {
        Text("Keys are stored in this device's Keychain. Captain's Log will only send requests directly to OpenAI after you choose a feature that needs cloud classification.")
            .kit941Font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func checkFormat(for candidate: String) {
        if let violation = AIProvider.openai.formatViolation(for: candidate) {
            message = violation
            messageIsError = true
        } else {
            message = "Key format looks valid."
            messageIsError = false
        }
    }

    private func test() async {
        guard let candidate = keyForTesting() else {
            message = "Paste or attach an OpenAI key first."
            messageIsError = true
            return
        }

        checkFormat(for: candidate)
        guard !messageIsError else {
            return
        }

        isTesting = true
        let result = await OpenAIWorkClassifier().testConnection(key: candidate)
        isTesting = false

        switch result {
        case .success:
            message = trimmedKey.isEmpty ? "Attached key works." : "OpenAI connection works. Save to attach it."
            messageIsError = false
        case .failure(let error):
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func save() {
        if let violation = AIProvider.openai.formatViolation(for: trimmedKey) {
            message = violation
            messageIsError = true
            return
        }

        guard store.saveKey(trimmedKey, for: .openai) else {
            message = "Keychain could not save this key."
            messageIsError = true
            return
        }

        key = ""
        refreshStoredKeyState()
        credentialRevision += 1
        message = "Key attached."
        messageIsError = false
    }

    private func delete() {
        store.deleteKey(for: .openai)
        key = ""
        refreshStoredKeyState()
        credentialRevision += 1
        message = "Key deleted."
        messageIsError = false
    }

    private func refreshStoredKeyState() {
        storedKeyPreview = store.keyPreview(for: .openai)
    }

    private func keyForTesting() -> String? {
        if !trimmedKey.isEmpty {
            return trimmedKey
        }
        return store.loadKey(for: .openai)
    }
}
