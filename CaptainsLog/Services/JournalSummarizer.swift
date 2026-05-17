import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum FoundationModelAvailability: Equatable {
    case available
    case unavailable(String)
}

struct JournalSummaryDraft: Codable, Equatable, Sendable {
    var title: String
    var narrative: String
    var bullets: [String]
    var tags: [String]
}

struct JournalSummaryResult: Equatable, Sendable {
    let draft: JournalSummaryDraft
    let modelName: String
}

enum JournalSummaryProvider: Equatable {
    case cloud(AIProvider)
    case appleFoundationModels

    var modelName: String {
        switch self {
        case .cloud(let provider): "\(provider.displayName) \(provider.shortModelName)"
        case .appleFoundationModels: "Apple Foundation Models"
        }
    }

    var symbolName: String {
        switch self {
        case .cloud(let provider): provider.symbolName
        case .appleFoundationModels: "apple.intelligence"
        }
    }

    static func preferred(
        credentialStore: AIProviderCredentialStore = .shared,
        foundationAvailability: FoundationModelAvailability
    ) -> JournalSummaryProvider? {
        let preferredProvider = credentialStore.preferredProvider
        if credentialStore.hasKey(for: preferredProvider) {
            return .cloud(preferredProvider)
        }
        if foundationAvailability == .available {
            return .appleFoundationModels
        }
        return nil
    }
}

struct JournalCommitEvidence: Sendable, Equatable, Identifiable {
    let id: String
    let shortSHA: String
    let repositoryFullName: String
    let messageHeadline: String
    let messageBody: String
    let authoredAt: Date

    init(
        id: String,
        shortSHA: String,
        repositoryFullName: String,
        messageHeadline: String,
        messageBody: String,
        authoredAt: Date
    ) {
        self.id = id
        self.shortSHA = shortSHA
        self.repositoryFullName = repositoryFullName
        self.messageHeadline = messageHeadline
        self.messageBody = messageBody
        self.authoredAt = authoredAt
    }

    init(record: GitCommitRecord) {
        self.id = record.id
        self.shortSHA = record.shortSHA
        self.repositoryFullName = record.repositoryFullName
        self.messageHeadline = record.messageHeadline
        self.messageBody = record.messageBody
        self.authoredAt = record.authoredAt
    }
}

enum JournalSummarizer {
    static func availability() -> FoundationModelAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This device does not support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in Settings to generate journal entries.")
        case .unavailable(.modelNotReady):
            return .unavailable("The local Apple Intelligence model is still downloading or preparing.")
        @unknown default:
            return .unavailable("The local Apple Intelligence model is unavailable right now.")
        }
        #else
        return .unavailable("Foundation Models is not available for this build.")
        #endif
    }

    static func generate(
        for date: Date,
        evidence: [JournalCommitEvidence],
        credentialStore: AIProviderCredentialStore = .shared
    ) async throws -> JournalSummaryResult {
        guard !evidence.isEmpty else {
            return JournalSummaryResult(
                draft: JournalSummaryDraft(
                    title: "No commits",
                    narrative: "No GitHub commits were imported for this day.",
                    bullets: [],
                    tags: []
                ),
                modelName: "Captain's Log"
            )
        }

        let provider = JournalSummaryProvider.preferred(
            credentialStore: credentialStore,
            foundationAvailability: availability()
        )
        guard let provider else {
            throw JournalSummaryError.unavailable("Add a cloud AI key or enable Apple Intelligence to generate journal entries.")
        }

        switch provider {
        case .cloud(let cloudProvider):
            let draft: JournalSummaryDraft
            switch cloudProvider {
            case .openai:
                draft = try await OpenAIJournalSummarizer(credentialStore: credentialStore)
                    .generate(for: date, evidence: evidence)
            case .anthropic:
                draft = try await AnthropicJournalSummarizer(credentialStore: credentialStore)
                    .generate(for: date, evidence: evidence)
            }
            return JournalSummaryResult(draft: draft, modelName: provider.modelName)
        case .appleFoundationModels:
            let draft = try await generateWithFoundationModels(for: date, evidence: evidence)
            return JournalSummaryResult(draft: draft, modelName: provider.modelName)
        }
    }

    private static func generateWithFoundationModels(for date: Date, evidence: [JournalCommitEvidence]) async throws -> JournalSummaryDraft {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(
            instructions: """
            You write a concise private work journal from Git commit evidence.
            Start with the memorable TL;DR of the day.
            Only describe work supported by the supplied commits.
            Do not invent shipped features, metrics, deployment status, customer impact, or unstated intent.
            Prefer concrete verbs. Keep the tone calm and factual.
            """
        )

        let response = try await session.respond(
            to: """
            Date:
            \(date.formatted(date: .complete, time: .omitted))

            Commits:
            \(commitEvidence(for: evidence))

            Write the daily entry.
            """,
            generating: FoundationJournalSummary.self,
            options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 700)
        )

        return JournalSummaryDraft(
            title: response.content.title,
            narrative: response.content.narrative,
            bullets: response.content.bullets,
            tags: response.content.tags
        )
        #else
        throw JournalSummaryError.unavailable("Foundation Models is not available for this build.")
        #endif
    }

    static func commitEvidence(for evidence: [JournalCommitEvidence]) -> String {
        evidence
            .sorted { $0.authoredAt < $1.authoredAt }
            .map { commit in
                let body = commit.messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
                let bodyLine = body.isEmpty ? "" : "\n  Body: \(body.prefix(280))"
                return """
                - \(commit.repositoryFullName) \(commit.shortSHA) \(commit.authoredAt.formatted(date: .omitted, time: .shortened))
                  Subject: \(commit.messageHeadline)\(bodyLine)
                """
            }
            .joined(separator: "\n")
    }
}

struct OpenAIJournalSummarizer: Sendable {
    static let modelName = OpenAIWorkClassifier.modelName

    var credentialStore: AIProviderCredentialStore = .shared
    var session: URLSession = .shared

    func generate(for date: Date, evidence: [JournalCommitEvidence]) async throws -> JournalSummaryDraft {
        guard let key = credentialStore.loadKey(for: .openai) else {
            throw OpenAIWorkClassifierError.missingKey
        }

        let payload: [String: Any] = [
            "model": Self.modelName,
            "input": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": Self.userPrompt(for: date, evidence: evidence)]
            ],
            "reasoning": ["effort": "low"],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "captains_log_daily_journal",
                    "strict": true,
                    "schema": Self.responseSchema
                ]
            ],
            "max_output_tokens": 1_200,
            "store": false
        ]

        let response = try await postJSON(
            URL(string: "https://api.openai.com/v1/responses")!,
            headers: [
                "Authorization": "Bearer \(key)",
                "Content-Type": "application/json"
            ],
            payload: payload
        )
        guard let text = OpenAIWorkClassifier.outputText(from: response),
              let data = text.data(using: .utf8) else {
            throw OpenAIWorkClassifierError.invalidResponse
        }
        return try JSONDecoder().decode(JournalSummaryDraft.self, from: data)
    }

    private func postJSON(_ url: URL, headers: [String: String], payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIWorkClassifierError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIWorkClassifierError.providerError(http.statusCode, String(body.prefix(320)))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIWorkClassifierError.invalidResponse
        }
        return object
    }

    private static func userPrompt(for date: Date, evidence: [JournalCommitEvidence]) -> String {
        """
        Date:
        \(date.formatted(date: .complete, time: .omitted))

        Commits:
        \(JournalSummarizer.commitEvidence(for: evidence))

        Write the daily entry.
        """
    }

    private static let systemPrompt = """
    You write a concise private work journal from Git commit evidence.
    Start with the memorable TL;DR of the day.
    Only describe work supported by the supplied commits.
    Do not invent shipped features, metrics, deployment status, customer impact, or unstated intent.
    Prefer concrete verbs. Keep the tone calm and factual.
    Return only JSON that matches the schema.
    """

    private static var responseSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "title": [
                    "type": "string",
                    "description": "Memorable TL;DR title for the day, 3 to 8 words"
                ],
                "narrative": [
                    "type": "string",
                    "description": "One short paragraph explaining what mattered that day"
                ],
                "bullets": [
                    "type": "array",
                    "items": ["type": "string"],
                    "minItems": 0,
                    "maxItems": 6,
                    "description": "Three to six concrete evidence bullets from the commits"
                ],
                "tags": [
                    "type": "array",
                    "items": ["type": "string"],
                    "minItems": 0,
                    "maxItems": 5
                ]
            ],
            "required": ["title", "narrative", "bullets", "tags"]
        ]
    }
}

enum CloudAIProviderError: LocalizedError, Equatable {
    case missingKey(AIProvider)
    case invalidResponse(AIProvider)
    case providerError(AIProvider, Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let provider):
            return "Add a \(provider.displayName) API key in AI settings."
        case .invalidResponse(let provider):
            return "\(provider.displayName) returned a response Captain's Log could not read."
        case .providerError(let provider, let status, _):
            return "\(provider.displayName) returned HTTP \(status)."
        }
    }
}

struct AnthropicJournalSummarizer: Sendable {
    static let modelName = "claude-sonnet-4-6"

    var credentialStore: AIProviderCredentialStore = .shared
    var session: URLSession = .shared

    func testConnection(key: String) async -> Result<Void, CloudAIProviderError> {
        guard AIProvider.anthropic.formatViolation(for: key) == nil else {
            return .failure(.missingKey(.anthropic))
        }

        let payload: [String: Any] = [
            "model": Self.modelName,
            "max_tokens": 8,
            "messages": [
                ["role": "user", "content": "Reply with ok."]
            ]
        ]

        do {
            _ = try await postData(
                URL(string: "https://api.anthropic.com/v1/messages")!,
                key: key,
                payload: payload,
                timeout: 12
            )
            return .success(())
        } catch let error as CloudAIProviderError {
            return .failure(error)
        } catch {
            return .failure(.invalidResponse(.anthropic))
        }
    }

    func generate(for date: Date, evidence: [JournalCommitEvidence]) async throws -> JournalSummaryDraft {
        guard let key = credentialStore.loadKey(for: .anthropic) else {
            throw CloudAIProviderError.missingKey(.anthropic)
        }

        let payload: [String: Any] = [
            "model": Self.modelName,
            "max_tokens": 1_200,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": Self.userPrompt(for: date, evidence: evidence)]
            ],
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": Self.responseSchema
                ]
            ]
        ]

        let data = try await postData(
            URL(string: "https://api.anthropic.com/v1/messages")!,
            key: key,
            payload: payload,
            timeout: 90
        )
        let response = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
        guard response.stopReason != "max_tokens",
              response.stopReason != "refusal",
              let text = response.outputText,
              let textData = text.data(using: .utf8) else {
            throw CloudAIProviderError.invalidResponse(.anthropic)
        }
        return try JSONDecoder().decode(JournalSummaryDraft.self, from: textData)
    }

    private func postData(_ url: URL, key: String, payload: [String: Any], timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudAIProviderError.invalidResponse(.anthropic)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CloudAIProviderError.providerError(.anthropic, http.statusCode, String(body.prefix(320)))
        }
        return data
    }

    private static func userPrompt(for date: Date, evidence: [JournalCommitEvidence]) -> String {
        """
        Date:
        \(date.formatted(date: .complete, time: .omitted))

        Commits:
        \(JournalSummarizer.commitEvidence(for: evidence))

        Write the daily entry.
        """
    }

    private static let systemPrompt = """
    You write a concise private work journal from Git commit evidence.
    Start with the memorable TL;DR of the day.
    Only describe work supported by the supplied commits.
    Do not invent shipped features, metrics, deployment status, customer impact, or unstated intent.
    Prefer concrete verbs. Keep the tone calm and factual.
    Return only JSON that matches the schema.
    """

    private static var responseSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "title": [
                    "type": "string",
                    "description": "Memorable TL;DR title for the day, 3 to 8 words"
                ],
                "narrative": [
                    "type": "string",
                    "description": "One short paragraph explaining what mattered that day"
                ],
                "bullets": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Three to six concrete evidence bullets from the commits"
                ],
                "tags": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "One to five short topic tags inferred from commit evidence"
                ]
            ],
            "required": ["title", "narrative", "bullets", "tags"]
        ]
    }
}

private struct AnthropicMessageResponse: Decodable {
    let content: [Content]
    let stopReason: String?

    var outputText: String? {
        let text = content.compactMap(\.text).joined()
        return text.isEmpty ? nil : text
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }

    struct Content: Decodable {
        let type: String
        let text: String?
    }
}

enum JournalSummaryError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

#if canImport(FoundationModels)
@Generable(description: "A daily developer journal entry based only on supplied Git commit evidence")
struct FoundationJournalSummary {
    @Guide(description: "Memorable TL;DR title for the day, 3 to 8 words")
    var title: String

    @Guide(description: "One short paragraph explaining what mattered that day")
    var narrative: String

    @Guide(description: "Three to six concrete accomplishment bullets", .count(3...6))
    var bullets: [String]

    @Guide(description: "One to five short topic tags inferred from commit evidence", .count(1...5))
    var tags: [String]
}
#endif
