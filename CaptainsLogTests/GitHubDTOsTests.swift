import XCTest
@testable import Captain_s_Log

final class GitHubDTOsTests: XCTestCase {
    func testGitHubAppInstallURLUsesDocumentedSlugRoute() {
        XCTAssertEqual(
            GitHubAppConfiguration.installURL?.absoluteString,
            "https://github.com/apps/941-captain-s-log/installations/new"
        )
    }

    func testDecodesViewerNodeIDForGraphQLAuthorFiltering() throws {
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

    func testGitHubCommitConflictCanBeTreatedAsEmptyHistory() {
        XCTAssertTrue(GitHubError.httpStatus(409, "{\"message\":\"Git Repository is empty.\"}").isCommitListConflict)
        XCTAssertFalse(GitHubError.httpStatus(404, "{\"message\":\"Not Found\"}").isCommitListConflict)
    }

    func testFullHistoryBackfillIsNotPageLimited() {
        XCTAssertNil(RepositoryHistoryBackfillPolicy.fullSyncCommitPageLimit)
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
