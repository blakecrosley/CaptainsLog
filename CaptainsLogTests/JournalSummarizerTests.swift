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

    func testOpenAIKeyWinsProviderSelection() {
        XCTAssertEqual(
            JournalSummaryProvider.preferred(hasOpenAIKey: true, foundationAvailability: .available),
            .openai
        )
        XCTAssertEqual(
            JournalSummaryProvider.preferred(hasOpenAIKey: true, foundationAvailability: .unavailable("Not ready")),
            .openai
        )
    }

    func testProviderSelectionFallsBackToAppleWithoutOpenAIKey() {
        XCTAssertEqual(
            JournalSummaryProvider.preferred(hasOpenAIKey: false, foundationAvailability: .available),
            .appleFoundationModels
        )
        XCTAssertNil(
            JournalSummaryProvider.preferred(hasOpenAIKey: false, foundationAvailability: .unavailable("Not ready"))
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
}
