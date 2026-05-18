import XCTest
@testable import Captain_s_Log

final class JournalSummarizerTests: XCTestCase {
    func testCommitEvidenceIncludesSourceRepoAndSHA() {
        let evidence = [
            JournalCommitEvidence(
                id: "owner/repo#abcdef123",
                shortSHA: "abcdef1",
                repositoryFullName: "owner/repo",
                messageHeadline: "Build contribution heatmap",
                messageBody: "",
                authoredAt: Date(timeIntervalSince1970: 1_767_808_800)
            )
        ]

        let text = JournalSummarizer.commitEvidence(for: evidence)

        XCTAssertTrue(text.contains("owner/repo"))
        XCTAssertTrue(text.contains("abcdef1"))
        XCTAssertTrue(text.contains("Build contribution heatmap"))
    }

    func testPreferredCloudKeyWinsProviderSelection() {
        let store = AIProviderCredentialStore(service: "test.captainslog.provider", inMemory: true)
        let openAIKey = ["sk", "test"].joined(separator: "-")
        store.preferredProvider = .openai
        XCTAssertTrue(store.saveKey(openAIKey, for: .openai))

        XCTAssertEqual(
            JournalSummaryProvider.preferred(credentialStore: store, foundationAvailability: .available),
            .cloud(.openai)
        )
        XCTAssertEqual(
            JournalSummaryProvider.preferred(credentialStore: store, foundationAvailability: .unavailable("Not ready")),
            .cloud(.openai)
        )
    }

    func testProviderSelectionFallsBackToAppleWithoutSelectedCloudKey() {
        let store = AIProviderCredentialStore(service: "test.captainslog.provider.fallback", inMemory: true)
        store.preferredProvider = .anthropic

        XCTAssertEqual(
            JournalSummaryProvider.preferred(credentialStore: store, foundationAvailability: .available),
            .appleFoundationModels
        )
        XCTAssertNil(
            JournalSummaryProvider.preferred(credentialStore: store, foundationAvailability: .unavailable("Not ready"))
        )
    }

    func testSummaryRecordPersistsGenerationModelName() {
        let date = Date(timeIntervalSince1970: 1_767_808_800)
        let record = DailyJournalSummaryRecord(
            date: date,
            title: "Initial",
            narrative: "Initial entry.",
            bullets: [],
            tags: [],
            sourceCommitIDs: [],
            modelName: "Apple Foundation Models"
        )
        let draft = JournalSummaryDraft(
            title: "OpenAI Entry",
            narrative: "Updated from commit evidence.",
            bullets: ["Built the journal provider switch."],
            tags: ["AI"]
        )

        record.update(from: draft, sourceCommitIDs: ["owner/repo#abc"], modelName: "OpenAI gpt-5.5")

        XCTAssertEqual(record.title, "OpenAI Entry")
        XCTAssertEqual(record.modelName, "OpenAI gpt-5.5")
        XCTAssertEqual(record.sourceCommitIDs, ["owner/repo#abc"])
    }

    func testLockedSummaryRecordRefusesOverwrite() {
        let date = Date(timeIntervalSince1970: 1_767_808_800)
        let record = DailyJournalSummaryRecord(
            date: date,
            title: "Kept Entry",
            narrative: "Keep this.",
            bullets: ["Original"],
            tags: ["Journal"],
            sourceCommitIDs: ["owner/repo#old"],
            modelName: "OpenAI gpt-5.5",
            isLocked: true
        )
        let draft = JournalSummaryDraft(
            title: "Replacement",
            narrative: "This should not be saved.",
            bullets: ["New"],
            tags: ["AI"]
        )

        let didUpdate = record.update(from: draft, sourceCommitIDs: ["owner/repo#new"], modelName: "Anthropic Claude")

        XCTAssertFalse(didUpdate)
        XCTAssertTrue(record.isLocked)
        XCTAssertEqual(record.title, "Kept Entry")
        XCTAssertEqual(record.narrative, "Keep this.")
        XCTAssertEqual(record.sourceCommitIDs, ["owner/repo#old"])
        XCTAssertEqual(record.modelName, "OpenAI gpt-5.5")
    }
}
