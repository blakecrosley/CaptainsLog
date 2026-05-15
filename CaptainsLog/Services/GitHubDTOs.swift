import Foundation

struct GitHubViewer: Decodable, Equatable {
    let login: String
    let nodeID: String?
    let name: String?
    let avatarURL: URL?
    let htmlURL: URL

    private enum CodingKeys: String, CodingKey {
        case login
        case nodeID = "node_id"
        case name
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
    }
}

struct GitHubRepositoryDTO: Decodable, Identifiable, Equatable {
    let id: Int64
    let name: String
    let fullName: String
    let isPrivate: Bool
    let htmlURL: URL
    let pushedAt: Date?
    let owner: GitHubOwnerDTO

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlURL = "html_url"
        case pushedAt = "pushed_at"
        case owner
    }
}

struct GitHubOwnerDTO: Decodable, Equatable {
    let login: String
}

struct GitHubInstallationDTO: Decodable, Identifiable, Equatable {
    let id: Int64
    let appID: Int64
    let appSlug: String?
    let htmlURL: URL?
    let repositorySelection: String
    let account: GitHubOwnerDTO?
    let permissions: GitHubInstallationPermissionsDTO?

    var canReadContents: Bool {
        permissions?.contents == "read" || permissions?.contents == "write"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case appID = "app_id"
        case appSlug = "app_slug"
        case htmlURL = "html_url"
        case repositorySelection = "repository_selection"
        case account
        case permissions
    }
}

struct GitHubInstallationPermissionsDTO: Decodable, Equatable {
    let metadata: String?
    let contents: String?
}

struct GitHubInstallationsResponse: Decodable, Equatable {
    let totalCount: Int
    let installations: [GitHubInstallationDTO]

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case installations
    }
}

struct GitHubRepositoriesResponse: Decodable, Equatable {
    let totalCount: Int
    let repositories: [GitHubRepositoryDTO]

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case repositories
    }
}

struct GitHubCommitDTO: Decodable, Equatable {
    let sha: String
    let htmlURL: URL
    let author: GitHubOwnerDTO?
    let commit: CommitPayload

    var message: String { commit.message }
    var authoredAt: Date { commit.author.date }

    private enum CodingKeys: String, CodingKey {
        case sha
        case htmlURL = "html_url"
        case author
        case commit
    }

    struct CommitPayload: Decodable, Equatable {
        let message: String
        let author: CommitAuthor
    }

    struct CommitAuthor: Decodable, Equatable {
        let date: Date
    }
}

struct GitHubCommitDetailDTO: Decodable, Equatable {
    let sha: String
    let htmlURL: URL?
    let stats: Stats?
    let files: [File]

    private enum CodingKeys: String, CodingKey {
        case sha
        case htmlURL = "html_url"
        case stats
        case files
    }

    struct Stats: Decodable, Equatable {
        let total: Int
        let additions: Int
        let deletions: Int
    }

    struct File: Decodable, Equatable {
        let filename: String
        let status: String?
        let additions: Int?
        let deletions: Int?
        let changes: Int?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try container.decode(String.self, forKey: .sha)
        htmlURL = try container.decodeIfPresent(URL.self, forKey: .htmlURL)
        stats = try container.decodeIfPresent(Stats.self, forKey: .stats)
        files = try container.decodeIfPresent([File].self, forKey: .files) ?? []
    }
}

struct GitHubCommitHistoryPage: Equatable {
    let commits: [GitHubGraphQLCommitDTO]
    let hasNextPage: Bool
    let endCursor: String?
}

struct GitHubGraphQLCommitDTO: Decodable, Equatable {
    let oid: String
    let message: String
    let authoredDate: Date
    let url: URL
    let additions: Int?
    let deletions: Int?
    let changedFilesIfAvailable: Int?
    let author: Author?

    var totalChanges: Int? {
        guard let additions, let deletions else {
            return nil
        }
        return additions + deletions
    }

    var authorLogin: String? {
        author?.user?.login
    }

    struct Author: Decodable, Equatable {
        let user: User?
    }

    struct User: Decodable, Equatable {
        let login: String
    }
}

struct GitHubCommitHistoryGraphQLData: Decodable, Equatable {
    let repository: Repository?

    var page: GitHubCommitHistoryPage {
        guard let history = repository?.defaultBranchRef?.target?.history else {
            return GitHubCommitHistoryPage(commits: [], hasNextPage: false, endCursor: nil)
        }

        return GitHubCommitHistoryPage(
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
        let nodes: [GitHubGraphQLCommitDTO]
        let pageInfo: PageInfo
    }

    struct PageInfo: Decodable, Equatable {
        let hasNextPage: Bool
        let endCursor: String?
    }
}

struct GitHubDeviceCodeResponse: Decodable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let expiresIn: Int
    let interval: Int

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct GitHubTokenResponse: Decodable, Equatable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
    }
}
