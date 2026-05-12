import Foundation

enum OpenAIWorkClassifierError: LocalizedError, Equatable {
    case missingKey
    case invalidResponse
    case providerError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add an OpenAI API key in AI settings."
        case .invalidResponse:
            return "OpenAI returned a response Captain's Log could not read."
        case .providerError(let status, _):
            return "OpenAI returned HTTP \(status)."
        }
    }
}

struct WorkClassificationRequest: Encodable, Equatable {
    let id: String
    let repository: String
    let headline: String
    let paths: [String]
    let additions: Int?
    let deletions: Int?
}

struct WorkClassificationResponse: Decodable, Equatable {
    let items: [Item]

    struct Item: Decodable, Equatable {
        let id: String
        let category: WorkCategory
        let confidence: Double
    }
}

struct OpenAIWorkClassifier: Sendable {
    static let modelName = "gpt-5.5"

    var credentialStore: AIProviderCredentialStore = .shared
    var session: URLSession = .shared

    func classify(_ commits: [GitCommitRecord]) async throws -> WorkClassificationResponse {
        guard let key = credentialStore.loadKey(for: .openai) else {
            throw OpenAIWorkClassifierError.missingKey
        }

        let requests = commits.map {
            WorkClassificationRequest(
                id: $0.id,
                repository: $0.repositoryFullName,
                headline: $0.messageHeadline,
                paths: $0.changedFiles,
                additions: $0.additions,
                deletions: $0.deletions
            )
        }

        return try await classify(requests, key: key)
    }

    func testConnection(key: String) async -> Result<Void, OpenAIWorkClassifierError> {
        guard AIProvider.openai.formatViolation(for: key) == nil else {
            return .failure(.missingKey)
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(.providerError(http.statusCode, ""))
            }
            return .success(())
        } catch {
            return .failure(.invalidResponse)
        }
    }

    func classify(_ requests: [WorkClassificationRequest], key: String) async throws -> WorkClassificationResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(requests)
        let requestText = String(data: requestData, encoding: .utf8) ?? "[]"

        let payload: [String: Any] = [
            "model": Self.modelName,
            "input": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": requestText]
            ],
            "reasoning": ["effort": "low"],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "captains_log_work_classification",
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
        guard let text = Self.outputText(from: response),
              let data = text.data(using: .utf8) else {
            throw OpenAIWorkClassifierError.invalidResponse
        }
        return try JSONDecoder().decode(WorkClassificationResponse.self, from: data)
    }

    private func postJSON(_ url: URL, headers: [String: String], payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
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

    static func outputText(from response: [String: Any]) -> String? {
        if let outputText = response["output_text"] as? String {
            return outputText
        }

        guard let output = response["output"] as? [[String: Any]] else {
            return nil
        }
        return output
            .compactMap { item -> String? in
                guard let content = item["content"] as? [[String: Any]] else {
                    return nil
                }
                return content.compactMap { $0["text"] as? String }.joined()
            }
            .joined()
    }

    private static let systemPrompt = """
    Classify each Git commit into exactly one Captain's Log work category.
    Valid categories: code, tests, docs, design, infra, release, unknown.
    Use file paths first. Use the headline only when paths are absent or ambiguous.
    Return only JSON that matches the schema.
    """

    private static var responseSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "id": ["type": "string"],
                            "category": [
                                "type": "string",
                                "enum": WorkCategory.allCases.map(\.rawValue)
                            ],
                            "confidence": [
                                "type": "number",
                                "minimum": 0,
                                "maximum": 1
                            ]
                        ],
                        "required": ["id", "category", "confidence"]
                    ]
                ]
            ],
            "required": ["items"]
        ]
    }
}
