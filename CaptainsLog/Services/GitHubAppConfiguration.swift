import Foundation

enum GitHubAppConfiguration {
    static let clientID = "Iv23lihLBqTFpOIrXba0"
    static let appID = "3678093"
    static let appSlug = "941-captain-s-log"

    static var installURL: URL? {
        URL(string: "https://github.com/apps/\(appSlug)/installations/new")
    }
}
