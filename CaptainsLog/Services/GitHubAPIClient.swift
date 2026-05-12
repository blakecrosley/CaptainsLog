import Foundation

struct GitHubAPIClient: Sendable {
    var token: String
    var appSlug: String? = nil

    private let apiBaseURL = URL(string: "https://api.github.com")!
    private let retryLimit = 2

    func viewer() async throws -> GitHubViewer {
        try await get(path: "/user")
    }

    func repositories() async throws -> [GitHubRepositoryDTO] {
        try await repositoryAccess().repositories
    }

    func repositoryAccess() async throws -> GitHubRepositoryAccess {
        let installations = try await appInstallations()
        guard !installations.isEmpty else {
            throw GitHubError.noAppInstallations(appSlug)
        }

        var repositoriesByID: [Int64: GitHubRepositoryDTO] = [:]
        for installation in installations {
            let repositories = try await installationRepositories(installationID: installation.id)
            for repository in repositories {
                repositoriesByID[repository.id] = repository
            }
        }

        let repositories = repositoriesByID.values.sorted { lhs, rhs in
            switch (lhs.pushedAt, rhs.pushedAt) {
            case let (left?, right?):
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
        }

        return GitHubRepositoryAccess(
            installations: installations,
            repositories: repositories
        )
    }

    func commits(
        owner: String,
        repo: String,
        author: String,
        since: Date
    ) async throws -> [GitHubCommitDTO] {
        do {
            return try await getAllPages(path: "/repos/\(owner)/\(repo)/commits", queryItems: [
                URLQueryItem(name: "author", value: author),
                URLQueryItem(name: "since", value: githubDateString(since)),
                URLQueryItem(name: "per_page", value: "100")
            ])
        } catch let error as GitHubError where error.isCommitListConflict {
            return []
        }
    }

    func commitPage(
        owner: String,
        repo: String,
        author: String,
        since: Date,
        until: Date? = nil,
        page: Int,
        perPage: Int = 100
    ) async throws -> [GitHubCommitDTO] {
        var queryItems = [
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "since", value: githubDateString(since)),
            URLQueryItem(name: "per_page", value: "\(perPage)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        if let until {
            queryItems.append(URLQueryItem(name: "until", value: githubDateString(until)))
        }
        do {
            return try await get(path: "/repos/\(owner)/\(repo)/commits", queryItems: queryItems)
        } catch let error as GitHubError where error.isCommitListConflict {
            return []
        }
    }

    func commitDetail(
        owner: String,
        repo: String,
        sha: String
    ) async throws -> GitHubCommitDetailDTO {
        try await get(path: "/repos/\(owner)/\(repo)/commits/\(sha)")
    }

    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let request = try makeRequest(path: path, queryItems: queryItems)

        for attempt in 0...retryLimit {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                try validate(response: response, data: data)
                return try GitHubJSON.decoder.decode(T.self, from: data)
            } catch {
                guard shouldRetry(error), attempt < retryLimit else {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 650_000_000)
            }
        }

        throw GitHubError.invalidResponse
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(url: apiBaseURL.appendingPathComponent(cleanPath), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw GitHubError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func getAllPages<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> [T] {
        var page = 1
        var all: [T] = []

        while true {
            var pageItems = queryItems
            pageItems.append(URLQueryItem(name: "page", value: "\(page)"))
            let batch: [T] = try await get(path: path, queryItems: pageItems)
            all.append(contentsOf: batch)
            if batch.count < 100 {
                return all
            }
            page += 1
        }
    }

    private func appInstallations() async throws -> [GitHubInstallationDTO] {
        var page = 1
        var all: [GitHubInstallationDTO] = []

        while true {
            let response: GitHubInstallationsResponse = try await get(path: "/user/installations", queryItems: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: "\(page)")
            ])
            all.append(contentsOf: response.installations)
            if response.installations.count < 100 {
                return all
            }
            page += 1
        }
    }

    private func installationRepositories(installationID: Int64) async throws -> [GitHubRepositoryDTO] {
        var page = 1
        var all: [GitHubRepositoryDTO] = []

        while true {
            let response: GitHubRepositoriesResponse = try await get(
                path: "/user/installations/\(installationID)/repositories",
                queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
            all.append(contentsOf: response.repositories)
            if response.repositories.count < 100 {
                return all
            }
            page += 1
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "GitHub request failed."
            throw GitHubError.httpStatus(http.statusCode, message)
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func githubDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

struct GitHubRepositoryAccess: Equatable {
    let installations: [GitHubInstallationDTO]
    let repositories: [GitHubRepositoryDTO]

    var approvalURL: URL? {
        installations.first?.htmlURL
    }

    var canReadContents: Bool {
        installations.contains { $0.canReadContents }
    }
}

struct GitHubDeviceAuthService: Sendable {
    let clientID: String

    func requestDeviceCode(scope: String? = nil) async throws -> GitHubDeviceCodeResponse {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubError.missingClientID
        }

        var fields = ["client_id": clientID]
        if let scope = scope?.trimmingCharacters(in: .whitespacesAndNewlines), !scope.isEmpty {
            fields["scope"] = scope
        }

        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try GitHubJSON.decoder.decode(GitHubDeviceCodeResponse.self, from: data)
    }

    func pollForToken(
        deviceCode: String,
        interval: Int,
        expiresIn: Int,
        waitBeforeFirstAttempt: Bool = true
    ) async throws -> String {
        var delay = max(interval, 5)
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        var shouldSleep = waitBeforeFirstAttempt

        while Date() < expiresAt {
            if shouldSleep {
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
            shouldSleep = true

            let response = try await tokenResponse(deviceCode: deviceCode)

            if let token = response.accessToken {
                return token
            }

            switch response.error {
            case "authorization_pending":
                continue
            case "slow_down":
                delay += 5
            case "expired_token":
                throw GitHubError.deviceCodeExpired
            case "access_denied":
                throw GitHubError.accessDenied
            case .some(let error):
                throw GitHubError.oauth(error, response.errorDescription)
            case .none:
                throw GitHubError.invalidResponse
            }
        }

        throw GitHubError.deviceCodeExpired
    }

    func exchangeDeviceCode(deviceCode: String) async throws -> String? {
        let response = try await tokenResponse(deviceCode: deviceCode)

        if let token = response.accessToken {
            return token
        }

        switch response.error {
        case "authorization_pending":
            return nil
        case "slow_down":
            return nil
        case "expired_token":
            throw GitHubError.deviceCodeExpired
        case "access_denied":
            throw GitHubError.accessDenied
        case .some(let error):
            throw GitHubError.oauth(error, response.errorDescription)
        case .none:
            throw GitHubError.invalidResponse
        }
    }

    private func tokenResponse(deviceCode: String) async throws -> GitHubTokenResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try GitHubJSON.decoder.decode(GitHubTokenResponse.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "GitHub auth failed."
            throw GitHubError.httpStatus(http.statusCode, message)
        }
    }

    private func formBody(_ values: [String: String]) -> Data {
        values
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}

enum GitHubJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum GitHubError: LocalizedError, Equatable {
    case missingClientID
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)
    case noAppInstallations(String?)
    case deviceCodeExpired
    case accessDenied
    case oauth(String, String?)

    var isCommitListConflict: Bool {
        guard case .httpStatus(409, _) = self else {
            return false
        }
        return true
    }

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Add a GitHub App Client ID to the GITHUB_CLIENT_ID build setting before connecting GitHub."
        case .invalidURL:
            return "The GitHub URL could not be built."
        case .invalidResponse:
            return "GitHub returned a response the app could not read."
        case .httpStatus(let status, let message):
            return "GitHub returned HTTP \(status): \(message)"
        case .noAppInstallations(let slug):
            if let slug, !slug.isEmpty {
                return "Approve repository access for Captain's Log, then refresh."
            }
            return "Approve access to at least one GitHub repository, then refresh."
        case .deviceCodeExpired:
            return "The GitHub sign-in code expired. Start again."
        case .accessDenied:
            return "GitHub sign-in was cancelled."
        case .oauth(let error, let description):
            return description ?? "GitHub sign-in returned \(error)."
        }
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
