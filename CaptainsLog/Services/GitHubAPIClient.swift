import Foundation

struct GitHubAPIClient: Sendable {
    var token: String
    var appSlug: String? = nil

    private let apiBaseURL = URL(string: "https://api.github.com")!
    private let graphQLURL = URL(string: "https://api.github.com/graphql")!
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
        since: Date
    ) async throws -> [GitHubCommitDTO] {
        do {
            return try await getAllPages(path: "/repos/\(owner)/\(repo)/commits", queryItems: [
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
        since: Date,
        until: Date? = nil,
        page: Int,
        perPage: Int = 100
    ) async throws -> [GitHubCommitDTO] {
        var queryItems = [
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

    func commitHistoryPage(
        owner: String,
        repo: String,
        since: Date,
        until: Date? = nil,
        after: String? = nil,
        perPage: Int = 100
    ) async throws -> GitHubCommitHistoryPage {
        let variables = CommitHistoryVariables(
            owner: owner,
            name: repo,
            since: githubDateString(since),
            until: until.map(githubDateString),
            after: after,
            first: perPage
        )
        do {
            let data: GitHubCommitHistoryGraphQLData = try await graphQL(
                query: Self.commitHistoryQuery,
                variables: variables
            )
            return data.page
        } catch {
            guard let gitHubError = error as? GitHubError,
                  gitHubError.isRecoverableCommitHistoryStatsFailure else {
                throw error
            }
            return try await commitHistoryPageWithRESTStatsFallback(
                owner: owner,
                repo: repo,
                variables: variables
            )
        }
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

    private func graphQL<T: Decodable, Variables: Encodable>(
        query: String,
        variables: Variables
    ) async throws -> T {
        var request = URLRequest(url: graphQLURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))

        for attempt in 0...retryLimit {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                try validate(response: response, data: data)
                let envelope = try GitHubJSON.decoder.decode(GraphQLResponse<T>.self, from: data)
                if let errors = envelope.errors, !errors.isEmpty {
                    throw GitHubError.graphQLErrors(errors.map(\.message))
                }
                guard let data = envelope.data else {
                    throw GitHubError.invalidResponse
                }
                return data
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
        if let gitHubError = error as? GitHubError {
            if case let .httpStatus(status, _) = gitHubError,
               [500, 502, 503, 504].contains(status) {
                return true
            }
        }

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

    private struct CommitHistoryVariables: Encodable {
        let owner: String
        let name: String
        let since: String
        let until: String?
        let after: String?
        let first: Int
    }

    private func commitHistoryPageWithRESTStatsFallback(
        owner: String,
        repo: String,
        variables: CommitHistoryVariables
    ) async throws -> GitHubCommitHistoryPage {
        let data: GitHubCommitIdentityHistoryGraphQLData = try await graphQL(
            query: Self.commitIdentityHistoryQuery,
            variables: variables
        )
        let identityPage = data.page
        var commits: [GitHubGraphQLCommitDTO] = []
        commits.reserveCapacity(identityPage.commits.count)

        for identity in identityPage.commits {
            try Task.checkCancellation()
            do {
                let detail = try await commitDetail(owner: owner, repo: repo, sha: identity.oid)
                commits.append(identity.graphQLCommit(with: detail))
            } catch {
                commits.append(identity.graphQLCommitWithoutDiffStats())
            }
        }

        return GitHubCommitHistoryPage(
            commits: commits,
            hasNextPage: identityPage.hasNextPage,
            endCursor: identityPage.endCursor
        )
    }

    private struct GraphQLRequest<Variables: Encodable>: Encodable {
        let query: String
        let variables: Variables
    }

    private struct GraphQLResponse<DataPayload: Decodable>: Decodable {
        let data: DataPayload?
        let errors: [GraphQLError]?
    }

    private struct GraphQLError: Decodable {
        let message: String
    }

    private struct GitHubCommitIdentityHistoryPage: Equatable {
        let commits: [GitHubCommitIdentityDTO]
        let hasNextPage: Bool
        let endCursor: String?
    }

    private struct GitHubCommitIdentityDTO: Decodable, Equatable {
        let oid: String
        let message: String
        let authoredDate: Date
        let url: URL
        let author: GitHubGraphQLCommitDTO.Author?

        func graphQLCommit(with detail: GitHubCommitDetailDTO) -> GitHubGraphQLCommitDTO {
            GitHubGraphQLCommitDTO(
                oid: oid,
                message: message,
                authoredDate: authoredDate,
                url: detail.htmlURL ?? url,
                additions: detail.stats?.additions,
                deletions: detail.stats?.deletions,
                changedFilesIfAvailable: detail.files.count,
                author: author
            )
        }

        func graphQLCommitWithoutDiffStats() -> GitHubGraphQLCommitDTO {
            GitHubGraphQLCommitDTO(
                oid: oid,
                message: message,
                authoredDate: authoredDate,
                url: url,
                additions: nil,
                deletions: nil,
                changedFilesIfAvailable: nil,
                author: author
            )
        }
    }

    private struct GitHubCommitIdentityHistoryGraphQLData: Decodable, Equatable {
        let repository: Repository?

        var page: GitHubCommitIdentityHistoryPage {
            guard let history = repository?.defaultBranchRef?.target?.history else {
                return GitHubCommitIdentityHistoryPage(commits: [], hasNextPage: false, endCursor: nil)
            }

            return GitHubCommitIdentityHistoryPage(
                commits: history.nodes,
                hasNextPage: history.pageInfo.hasNextPage,
                endCursor: history.pageInfo.endCursor
            )
        }

        struct Repository: Decodable, Equatable {
            let defaultBranchRef: Ref?
        }

        struct Ref: Decodable, Equatable {
            let target: Target?
        }

        struct Target: Decodable, Equatable {
            let history: History?
        }

        struct History: Decodable, Equatable {
            let nodes: [GitHubCommitIdentityDTO]
            let pageInfo: GitHubCommitHistoryGraphQLData.PageInfo
        }
    }

    private static let commitHistoryQuery = """
    query CaptainLogCommitHistory($owner: String!, $name: String!, $since: GitTimestamp!, $until: GitTimestamp, $after: String, $first: Int!) {
      repository(owner: $owner, name: $name) {
        defaultBranchRef {
          target {
            ... on Commit {
              history(first: $first, after: $after, since: $since, until: $until) {
                pageInfo {
                  hasNextPage
                  endCursor
                }
                nodes {
                  oid
                  message
                  authoredDate
                  url
                  additions
                  deletions
                  changedFilesIfAvailable
                  author {
                    user {
                      login
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    private static let commitIdentityHistoryQuery = """
    query CaptainLogCommitIdentityHistory($owner: String!, $name: String!, $since: GitTimestamp!, $until: GitTimestamp, $after: String, $first: Int!) {
      repository(owner: $owner, name: $name) {
        defaultBranchRef {
          target {
            ... on Commit {
              history(first: $first, after: $after, since: $since, until: $until) {
                pageInfo {
                  hasNextPage
                  endCursor
                }
                nodes {
                  oid
                  message
                  authoredDate
                  url
                  author {
                    user {
                      login
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    """
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

struct GitHubOAuthSession: Codable, Equatable {
    let accessToken: String
    let accessTokenExpiresAt: Date?
    let refreshToken: String?
    let refreshTokenExpiresAt: Date?

    init(
        accessToken: String,
        accessTokenExpiresAt: Date? = nil,
        refreshToken: String? = nil,
        refreshTokenExpiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }

    init(response: GitHubTokenResponse, receivedAt: Date = Date()) throws {
        guard let accessToken = response.accessToken else {
            throw GitHubError.invalidResponse
        }
        self.accessToken = accessToken
        self.accessTokenExpiresAt = response.expiresIn.map { receivedAt.addingTimeInterval(TimeInterval($0)) }
        self.refreshToken = response.refreshToken
        self.refreshTokenExpiresAt = response.refreshTokenExpiresIn.map { receivedAt.addingTimeInterval(TimeInterval($0)) }
    }

    func shouldRefresh(now: Date = Date(), leeway: TimeInterval = 300) -> Bool {
        guard let accessTokenExpiresAt else {
            return false
        }
        return now >= accessTokenExpiresAt.addingTimeInterval(-leeway)
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

            if response.accessToken != nil {
                return try GitHubOAuthSession(response: response).accessToken
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
        try await exchangeDeviceSession(deviceCode: deviceCode)?.accessToken
    }

    func exchangeDeviceSession(deviceCode: String) async throws -> GitHubOAuthSession? {
        let response = try await tokenResponse(deviceCode: deviceCode)

        if response.accessToken != nil {
            return try GitHubOAuthSession(response: response)
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

    func refreshSession(refreshToken: String) async throws -> GitHubOAuthSession {
        let response = try await refreshTokenResponse(refreshToken: refreshToken)
        return try GitHubOAuthSession(response: response)
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

    private func refreshTokenResponse(refreshToken: String) async throws -> GitHubTokenResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let tokenResponse = try GitHubJSON.decoder.decode(GitHubTokenResponse.self, from: data)
        if let error = tokenResponse.error {
            throw GitHubError.oauth(error, tokenResponse.errorDescription)
        }
        return tokenResponse
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
    case graphQLErrors([String])
    case deviceCodeExpired
    case accessDenied
    case oauth(String, String?)

    var isCommitListConflict: Bool {
        guard case .httpStatus(409, _) = self else {
            return false
        }
        return true
    }

    var isUnauthorized: Bool {
        guard case .httpStatus(401, _) = self else {
            return false
        }
        return true
    }

    var isRefreshTokenInvalid: Bool {
        guard case .oauth(let error, _) = self else {
            return false
        }
        return error == "bad_refresh_token" || error == "expired_token"
    }

    var isRecoverableCommitHistoryStatsFailure: Bool {
        switch self {
        case .httpStatus(let status, _):
            return [500, 502, 503, 504].contains(status)
        case .graphQLErrors(let messages):
            return messages.contains { message in
                let lowercased = message.lowercased()
                return lowercased.contains("count for this commit is unavailable") ||
                    lowercased.contains("additions count") ||
                    lowercased.contains("deletions count") ||
                    lowercased.contains("changed files")
            }
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Add a GitHub App Client ID to the GITHUB_CLIENT_ID build setting before connecting GitHub."
        case .invalidURL:
            return "The GitHub URL could not be built."
        case .invalidResponse:
            return "GitHub returned a response the app could not read."
        case .httpStatus(401, _):
            return "GitHub rejected the saved session. Sign in again."
        case .httpStatus(let status, let message):
            return "GitHub returned HTTP \(status): \(message)"
        case .noAppInstallations(let slug):
            if let slug, !slug.isEmpty {
                return "Approve repository access for Captain's Log, then refresh."
            }
            return "Approve access to at least one GitHub repository, then refresh."
        case .graphQLErrors(let messages):
            return "GitHub GraphQL returned: \(messages.joined(separator: "; "))"
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
