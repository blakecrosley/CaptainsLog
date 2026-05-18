import SwiftData
import Security
import XCTest
@testable import Captain_s_Log

final class GitHubDTOsTests: XCTestCase {
    func testGitHubAppInstallURLUsesDocumentedSlugRoute() {
        XCTAssertEqual(
            GitHubAppConfiguration.installURL?.absoluteString,
            "https://github.com/apps/941-captain-s-log/installations/new"
        )
    }

    func testBackgroundHistoryIndexerUsesPermittedIdentifier() {
        XCTAssertEqual(
            BackgroundHistoryIndexer.taskIdentifier,
            "com.blakecrosley.captainslog.history-index"
        )
        XCTAssertEqual(BackgroundHistoryIndexer.lookbackDays, 7_300)
        XCTAssertEqual(BackgroundHistoryIndexer.defaultEarliestDelay, 30 * 60)
    }

    func testHotSyncPolicyKeepsForegroundRefreshSmall() {
        XCTAssertEqual(RepositoryHotSyncPolicy.lookbackDays, 14)
        XCTAssertEqual(RepositoryHotSyncPolicy.minimumForegroundInterval, 120)
    }

    func testKeychainMissingEntitlementIsRecognizedForStartupRestore() {
        XCTAssertTrue(KeychainError.unhandled(errSecMissingEntitlement).isMissingEntitlement)
        XCTAssertFalse(KeychainError.unhandled(errSecAuthFailed).isMissingEntitlement)
        XCTAssertFalse(KeychainError.invalidData.isMissingEntitlement)
    }

    func testDecodesViewerNodeIDForSessionIdentity() throws {
        let json = Data("""
        {
          "login": "blakecrosley",
          "node_id": "MDQ6VXNlcjk0MQ==",
          "name": "Blake Crosley",
          "avatar_url": "https://avatars.githubusercontent.com/u/941?v=4",
          "html_url": "https://github.com/blakecrosley"
        }
        """.utf8)

        let viewer = try GitHubJSON.decoder.decode(GitHubViewer.self, from: json)

        XCTAssertEqual(viewer.login, "blakecrosley")
        XCTAssertEqual(viewer.nodeID, "MDQ6VXNlcjk0MQ==")
    }

    func testDecodesExpiringGitHubAppUserToken() throws {
        let json = Data("""
        {
          "access_token": "ghu_access",
          "expires_in": 28800,
          "refresh_token": "ghr_refresh",
          "refresh_token_expires_in": 15897600,
          "scope": "",
          "token_type": "bearer"
        }
        """.utf8)

        let response = try GitHubJSON.decoder.decode(GitHubTokenResponse.self, from: json)
        let session = try GitHubOAuthSession(
            response: response,
            receivedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(session.accessToken, "ghu_access")
        XCTAssertEqual(session.accessTokenExpiresAt, Date(timeIntervalSince1970: 29_800))
        XCTAssertEqual(session.refreshToken, "ghr_refresh")
        XCTAssertEqual(session.refreshTokenExpiresAt, Date(timeIntervalSince1970: 15_898_600))
    }

    func testEmptyLocalRepositorySyncIgnoresStaleLastSyncedAt() throws {
        let calendar = Calendar(identifier: .gregorian)
        let fallbackSince = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let staleLastSync = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))

        let updateSince = RepositorySyncWindow.updateSince(
            fallbackSince: fallbackSince,
            lastSyncedAt: staleLastSync,
            newestCommitDate: nil,
            overlap: 300
        )

        XCTAssertEqual(updateSince, fallbackSince)
    }

    func testLatestSyncCanForceRollingLookbackWindow() throws {
        let calendar = Calendar(identifier: .gregorian)
        let fallbackSince = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let lastSyncedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 12)))
        let newestCommitDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 14, hour: 18)))

        let updateSince = RepositorySyncWindow.updateSince(
            fallbackSince: fallbackSince,
            lastSyncedAt: lastSyncedAt,
            newestCommitDate: newestCommitDate,
            overlap: 300,
            minimumRescanSince: fallbackSince
        )

        XCTAssertEqual(updateSince, fallbackSince)
    }

    func testIncrementalSyncStillUsesNewestSafeWindowWithoutForcedLookback() throws {
        let calendar = Calendar(identifier: .gregorian)
        let fallbackSince = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let lastSyncedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 12)))
        let newestCommitDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 14, hour: 18)))

        let updateSince = RepositorySyncWindow.updateSince(
            fallbackSince: fallbackSince,
            lastSyncedAt: lastSyncedAt,
            newestCommitDate: newestCommitDate,
            overlap: 300
        )

        XCTAssertEqual(updateSince, lastSyncedAt.addingTimeInterval(-300))
    }

    func testDemoRepositoryIsNotGitHubBacked() {
        let demo = GitRepositoryRecord(
            id: -941,
            ownerLogin: "captains-log",
            name: "demo",
            fullName: "captains-log/demo",
            isPrivate: false
        )
        let remote = GitRepositoryRecord(
            id: 941,
            ownerLogin: "blakecrosley",
            name: "captains-log",
            fullName: "blakecrosley/captains-log",
            isPrivate: true
        )

        XCTAssertFalse(demo.isGitHubBacked)
        XCTAssertTrue(remote.isGitHubBacked)
    }

    @MainActor
    func testClearImportedHistoryDeletesLocalHistoryAndPreservesRepositorySetup() throws {
        let schema = Schema([
            GitHubAccountRecord.self,
            GitRepositoryRecord.self,
            GitCommitRecord.self,
            DailyJournalSummaryRecord.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let appModel = AppModel()
        appModel.configure(modelContext: context)

        let syncDate = Date(timeIntervalSince1970: 1_000)
        let repo = GitRepositoryRecord(
            id: 941,
            ownerLogin: "blakecrosley",
            name: "captains-log",
            fullName: "blakecrosley/captains-log",
            accountLogin: "blakecrosley",
            isPrivate: true,
            isSelected: true,
            lastSyncedAt: syncDate
        )
        repo.historyBackfillLowerBound = Date(timeIntervalSince1970: 500)
        repo.historyBackfillCursorDate = Date(timeIntervalSince1970: 600)
        repo.historyBackfillCompletedAt = syncDate
        repo.historyBackfillProcessedCommitCount = 12
        repo.historyBackfillUpdatedStatCount = 8

        let commit = GitCommitRecord(
            sha: "abcdef1234567890",
            repositoryFullName: repo.fullName,
            authorLogin: "blakecrosley",
            message: "Add privacy controls",
            authoredAt: syncDate,
            htmlURL: nil
        )
        commit.applyDiffStats(additions: 20, deletions: 4, changedFileCount: 2)
        commit.repository = repo

        let summary = DailyJournalSummaryRecord(
            date: syncDate,
            title: "Privacy controls",
            narrative: "Added a local data control.",
            bullets: ["Cleared imported history"],
            tags: ["Privacy"],
            sourceCommitIDs: [commit.id]
        )

        context.insert(repo)
        context.insert(commit)
        context.insert(summary)
        try context.save()

        let result = try appModel.clearImportedHistory()

        XCTAssertEqual(result.deletedCommitCount, 1)
        XCTAssertEqual(result.deletedJournalCount, 1)
        XCTAssertEqual(result.resetRepositoryCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GitCommitRecord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyJournalSummaryRecord>()).count, 0)

        let repositories = try context.fetch(FetchDescriptor<GitRepositoryRecord>())
        let preservedRepo = try XCTUnwrap(repositories.first)
        XCTAssertEqual(repositories.count, 1)
        XCTAssertEqual(preservedRepo.fullName, "blakecrosley/captains-log")
        XCTAssertTrue(preservedRepo.isSelected)
        XCTAssertNil(preservedRepo.lastSyncedAt)
        XCTAssertNil(preservedRepo.historyBackfillLowerBound)
        XCTAssertNil(preservedRepo.historyBackfillCursorDate)
        XCTAssertNil(preservedRepo.historyBackfillCompletedAt)
        XCTAssertNil(preservedRepo.historyBackfillProcessedCommitCount)
        XCTAssertNil(preservedRepo.historyBackfillUpdatedStatCount)
    }

    func testDecodesGitHubAppInstallationsResponse() throws {
        let json = Data("""
        {
          "total_count": 1,
          "installations": [
            {
              "id": 123,
              "app_id": 3678093,
              "app_slug": "941-captain-s-log",
              "html_url": "https://github.com/settings/installations/123",
              "repository_selection": "selected",
              "account": { "login": "blakecrosley" },
              "permissions": {
                "metadata": "read",
                "contents": "read"
              }
            }
          ]
        }
        """.utf8)

        let response = try GitHubJSON.decoder.decode(GitHubInstallationsResponse.self, from: json)

        XCTAssertEqual(response.totalCount, 1)
        XCTAssertEqual(response.installations.first?.id, 123)
        XCTAssertEqual(response.installations.first?.appID, 3_678_093)
        XCTAssertEqual(response.installations.first?.appSlug, "941-captain-s-log")
        XCTAssertEqual(response.installations.first?.htmlURL?.absoluteString, "https://github.com/settings/installations/123")
        XCTAssertEqual(response.installations.first?.repositorySelection, "selected")
        XCTAssertEqual(response.installations.first?.account?.login, "blakecrosley")
        XCTAssertEqual(response.installations.first?.permissions?.contents, "read")
        XCTAssertEqual(response.installations.first?.canReadContents, true)
    }

    func testDecodesInstallationRepositoriesResponse() throws {
        let json = Data("""
        {
          "total_count": 1,
          "repositories": [
            {
              "id": 941,
              "name": "captains-log",
              "full_name": "blakecrosley/captains-log",
              "private": true,
              "html_url": "https://github.com/blakecrosley/captains-log",
              "pushed_at": "2026-05-11T12:34:56Z",
              "owner": { "login": "blakecrosley" }
            }
          ]
        }
        """.utf8)

        let response = try GitHubJSON.decoder.decode(GitHubRepositoriesResponse.self, from: json)

        XCTAssertEqual(response.totalCount, 1)
        XCTAssertEqual(response.repositories.first?.id, 941)
        XCTAssertEqual(response.repositories.first?.fullName, "blakecrosley/captains-log")
        XCTAssertEqual(response.repositories.first?.owner.login, "blakecrosley")
        XCTAssertEqual(response.repositories.first?.isPrivate, true)
        XCTAssertNotNil(response.repositories.first?.pushedAt)
    }

    func testDecodesGitHubCommitResponse() throws {
        let json = Data("""
        [
          {
            "sha": "abcdef1234567890",
            "html_url": "https://github.com/blakecrosley/captains-log/commit/abcdef1",
            "author": { "login": "blakecrosley" },
            "commit": {
              "message": "Fix resumegeni sync\\n\\nPersist commit pages as they arrive.",
              "author": {
                "date": "2026-05-11T18:42:00Z"
              }
            }
          }
        ]
        """.utf8)

        let commits = try GitHubJSON.decoder.decode([GitHubCommitDTO].self, from: json)

        XCTAssertEqual(commits.first?.sha, "abcdef1234567890")
        XCTAssertEqual(commits.first?.author?.login, "blakecrosley")
        XCTAssertEqual(commits.first?.message, "Fix resumegeni sync\n\nPersist commit pages as they arrive.")
        XCTAssertNotNil(commits.first?.authoredAt)
    }

    func testDecodesUnlinkedGitAuthorFromCommitResponse() throws {
        let json = Data("""
        [
          {
            "sha": "abcdef1234567890",
            "html_url": "https://github.com/blakecrosley/hermes-brain/commit/abcdef1",
            "author": null,
            "commit": {
              "message": "verify-prd",
              "author": {
                "name": "Blake",
                "email": "blake@local",
                "date": "2026-04-10T03:40:13Z"
              }
            }
          }
        ]
        """.utf8)

        let commits = try GitHubJSON.decoder.decode([GitHubCommitDTO].self, from: json)

        XCTAssertEqual(commits.first?.sha, "abcdef1234567890")
        XCTAssertNil(commits.first?.author?.login)
        XCTAssertNotNil(commits.first?.authoredAt)
    }

    func testDecodesGitHubCommitDetailStats() throws {
        let json = Data("""
        {
          "sha": "abcdef1234567890",
          "html_url": "https://github.com/blakecrosley/captains-log/commit/abcdef1",
          "stats": {
            "total": 42,
            "additions": 30,
            "deletions": 12
          },
          "files": [
            {
              "filename": "CaptainsLog/Models/WorkMetrics.swift",
              "status": "added",
              "additions": 30,
              "deletions": 0,
              "changes": 30
            },
            {
              "filename": "CaptainsLog/Views/RootView.swift",
              "status": "modified",
              "additions": 0,
              "deletions": 12,
              "changes": 12
            }
          ]
        }
        """.utf8)

        let detail = try GitHubJSON.decoder.decode(GitHubCommitDetailDTO.self, from: json)

        XCTAssertEqual(detail.sha, "abcdef1234567890")
        XCTAssertEqual(detail.stats?.total, 42)
        XCTAssertEqual(detail.stats?.additions, 30)
        XCTAssertEqual(detail.stats?.deletions, 12)
        XCTAssertEqual(detail.files.map(\.filename), [
            "CaptainsLog/Models/WorkMetrics.swift",
            "CaptainsLog/Views/RootView.swift"
        ])
    }

    func testDecodesGitHubGraphQLCommitHistoryWithDiffStats() throws {
        struct Envelope: Decodable {
            let data: GitHubCommitHistoryGraphQLData
        }

        let json = Data("""
        {
          "data": {
            "repository": {
              "defaultBranchRef": {
                "target": {
                  "history": {
                    "pageInfo": {
                      "hasNextPage": true,
                      "endCursor": "history-cursor"
                    },
                    "nodes": [
                      {
                        "oid": "abcdef1234567890",
                        "message": "Measure changed lines",
                        "authoredDate": "2026-05-11T18:42:00Z",
                        "url": "https://github.com/blakecrosley/captains-log/commit/abcdef1",
                        "additions": 120,
                        "deletions": 35,
                        "changedFilesIfAvailable": 7,
                        "author": {
                          "user": {
                            "login": "blakecrosley"
                          }
                        }
                      }
                    ]
                  }
                }
              }
            }
          }
        }
        """.utf8)

        let envelope = try GitHubJSON.decoder.decode(Envelope.self, from: json)
        let page = envelope.data.page

        XCTAssertEqual(page.commits.count, 1)
        XCTAssertTrue(page.hasNextPage)
        XCTAssertEqual(page.endCursor, "history-cursor")
        XCTAssertEqual(page.commits.first?.oid, "abcdef1234567890")
        XCTAssertEqual(page.commits.first?.additions, 120)
        XCTAssertEqual(page.commits.first?.deletions, 35)
        XCTAssertEqual(page.commits.first?.totalChanges, 155)
        XCTAssertEqual(page.commits.first?.changedFilesIfAvailable, 7)
        XCTAssertEqual(page.commits.first?.authorLogin, "blakecrosley")
    }

    func testDecodesGitHubGraphQLCommitHistoryWithUnlinkedAuthor() throws {
        struct Envelope: Decodable {
            let data: GitHubCommitHistoryGraphQLData
        }

        let json = Data("""
        {
          "data": {
            "repository": {
              "defaultBranchRef": {
                "target": {
                  "history": {
                    "pageInfo": {
                      "hasNextPage": false,
                      "endCursor": null
                    },
                    "nodes": [
                      {
                        "oid": "7fb067b1234567890",
                        "message": "verify-prd",
                        "authoredDate": "2026-04-10T03:40:13Z",
                        "url": "https://github.com/blakecrosley/hermes-brain/commit/7fb067b",
                        "additions": 10,
                        "deletions": 2,
                        "changedFilesIfAvailable": 1,
                        "author": {
                          "user": null
                        }
                      }
                    ]
                  }
                }
              }
            }
          }
        }
        """.utf8)

        let envelope = try GitHubJSON.decoder.decode(Envelope.self, from: json)
        let page = envelope.data.page

        XCTAssertEqual(page.commits.count, 1)
        XCTAssertEqual(page.commits.first?.totalChanges, 12)
        XCTAssertNil(page.commits.first?.authorLogin)
    }

    func testGraphQLCommitHistoryCanRepresentMissingDiffStats() throws {
        struct Envelope: Decodable {
            let data: GitHubCommitHistoryGraphQLData
        }

        let json = Data("""
        {
          "data": {
            "repository": {
              "defaultBranchRef": {
                "target": {
                  "history": {
                    "pageInfo": {
                      "hasNextPage": false,
                      "endCursor": null
                    },
                    "nodes": [
                      {
                        "oid": "missingstats123",
                        "message": "commit with unavailable stat fields",
                        "authoredDate": "2026-01-22T18:00:00Z",
                        "url": "https://github.com/blakecrosley/resumegeni/commit/missingstats123",
                        "additions": null,
                        "deletions": null,
                        "changedFilesIfAvailable": null,
                        "author": {
                          "user": {
                            "login": "blakecrosley"
                          }
                        }
                      }
                    ]
                  }
                }
              }
            }
          }
        }
        """.utf8)

        let envelope = try GitHubJSON.decoder.decode(Envelope.self, from: json)
        let commit = try XCTUnwrap(envelope.data.page.commits.first)

        XCTAssertNil(commit.additions)
        XCTAssertNil(commit.deletions)
        XCTAssertNil(commit.totalChanges)
        XCTAssertEqual(commit.authorLogin, "blakecrosley")
    }

    func testGitHubCommitConflictCanBeTreatedAsEmptyHistory() {
        XCTAssertTrue(GitHubError.httpStatus(409, "{\"message\":\"Git Repository is empty.\"}").isCommitListConflict)
        XCTAssertFalse(GitHubError.httpStatus(404, "{\"message\":\"Not Found\"}").isCommitListConflict)
    }

    func testGitHubUnauthorizedIsSessionFailure() {
        let error = GitHubError.httpStatus(401, "{\"message\":\"Bad credentials\"}")

        XCTAssertTrue(error.isUnauthorized)
        XCTAssertEqual(error.localizedDescription, "GitHub rejected the saved session. Sign in again.")
    }

    func testCommitHistoryStatsFailuresCanUseRESTFallback() {
        let unavailableCount = GitHubError.graphQLErrors([
            "The additions count for this commit is unavailable."
        ])
        let serviceUnavailable = GitHubError.httpStatus(502, "Bad Gateway")
        let unauthorized = GitHubError.httpStatus(401, "Bad credentials")

        XCTAssertTrue(unavailableCount.isRecoverableCommitHistoryStatsFailure)
        XCTAssertTrue(serviceUnavailable.isRecoverableCommitHistoryStatsFailure)
        XCTAssertFalse(unauthorized.isRecoverableCommitHistoryStatsFailure)
    }

    func testFullHistoryBackfillIsNotPageLimited() {
        XCTAssertNil(RepositoryHistoryBackfillPolicy.fullSyncCommitPageLimit)
    }

    func testHistoricalIndexRunHasEnoughPageBudgetForRealHistory() {
        XCTAssertGreaterThanOrEqual(RepositoryHistoryBackfillPolicy.indexPageBudgetPerRun, 300)
    }

    func testOpenAIOutputTextReadsResponsesShape() {
        let response: [String: Any] = [
            "output": [
                [
                    "content": [
                        [
                            "type": "output_text",
                            "text": #"{"items":[]}"#
                        ]
                    ]
                ]
            ]
        ]

        XCTAssertEqual(OpenAIWorkClassifier.outputText(from: response), #"{"items":[]}"#)
    }
}
