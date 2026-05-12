import Foundation

enum WorkCategory: String, CaseIterable, Codable, Identifiable {
    case code
    case tests
    case docs
    case design
    case infra
    case release
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .code: "Code"
        case .tests: "Tests"
        case .docs: "Docs"
        case .design: "Design"
        case .infra: "Infra"
        case .release: "Release"
        case .unknown: "Unknown"
        }
    }
}

enum WorkClassifier {
    static func category(for commit: GitCommitRecord) -> WorkCategory {
        let paths = commit.changedFiles
        if let category = category(from: paths) {
            return category
        }
        return category(fromHeadline: commit.messageHeadline)
    }

    private static func category(from paths: [String]) -> WorkCategory? {
        guard !paths.isEmpty else {
            return nil
        }

        let categories = paths.map(category(fromPath:))
        let known = categories.filter { $0 != .unknown }
        guard !known.isEmpty else {
            return nil
        }

        return Dictionary(grouping: known, by: { $0 })
            .max { lhs, rhs in lhs.value.count < rhs.value.count }?
            .key
    }

    private static func category(fromPath path: String) -> WorkCategory {
        let lower = path.lowercased()
        let extensionName = URL(fileURLWithPath: lower).pathExtension

        if lower.contains("/test") || lower.contains("tests/") || lower.contains("spec/") || lower.contains("snapshot") {
            return .tests
        }
        if ["md", "mdx", "txt", "rst", "docx"].contains(extensionName) || lower.contains("docs/") || lower.contains("content/") {
            return .docs
        }
        if lower.contains(".github/") || lower.contains("dockerfile") || lower.contains("fastlane/") || lower.contains("terraform") || lower.contains("package-lock") || lower.contains("pnpm-lock") {
            return .infra
        }
        if lower.contains("asset") || lower.contains("design") || ["xcassets", "png", "jpg", "jpeg", "webp", "svg"].contains(extensionName) {
            return .design
        }
        if lower.contains("release") || lower.contains("changelog") {
            return .release
        }
        if ["swift", "js", "ts", "tsx", "jsx", "py", "go", "rb", "rs", "java", "kt", "c", "cpp", "h", "m", "mm", "html", "css"].contains(extensionName) {
            return .code
        }
        return .unknown
    }

    private static func category(fromHeadline headline: String) -> WorkCategory {
        let lower = headline.lowercased()
        if lower.contains("test") || lower.contains("spec") {
            return .tests
        }
        if lower.contains("doc") || lower.contains("copy") || lower.contains("content") || lower.contains("blog") {
            return .docs
        }
        if lower.contains("ui") || lower.contains("design") || lower.contains("layout") || lower.contains("polish") {
            return .design
        }
        if lower.contains("deploy") || lower.contains("ci") || lower.contains("build") || lower.contains("sync") {
            return .infra
        }
        if lower.contains("release") || lower.contains("version") {
            return .release
        }
        return .code
    }
}
