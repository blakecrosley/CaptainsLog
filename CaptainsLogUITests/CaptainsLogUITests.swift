import XCTest

@MainActor
final class CaptainsLogUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstRunKeepsPrimaryActionsReadable() throws {
        let app = launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Captain's Log"].waitForExistence(timeout: 6))
        XCTAssertTrue(actionRow("Sign in with GitHub", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(actionRow("Use Demo Data", in: app).waitForExistence(timeout: 3))
    }

    func testFixtureDashboardExposesSettingsAndDayDetail() throws {
        let app = launchApp(fixture: true)
        defer { app.terminate() }

        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[fixtureShowcaseDayTitle].waitForExistence(timeout: 3))

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(actionRow("Update Now", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(actionRow("GitHub Access", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(actionRow("History Coverage", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(actionRow("Privacy & Data", in: app).waitForExistence(timeout: 3))
        actionRow("Privacy & Data", in: app).tap()
        XCTAssertTrue(app.navigationBars["Privacy & Data"].waitForExistence(timeout: 3))
        XCTAssertTrue(actionRow("Clear Imported History", in: app).waitForExistence(timeout: 3))
        let settingsBackButton = app.navigationBars["Privacy & Data"].buttons["Settings"]
        XCTAssertTrue(settingsBackButton.waitForExistence(timeout: 3))
        settingsBackButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 3))
        doneButton.tap()

        let openDayDetail = app.buttons["Open selected day detail"]
        XCTAssertTrue(openDayDetail.waitForExistence(timeout: 3))
        openDayDetail.tap()
        XCTAssertTrue(app.buttons["Regenerate journal"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Commits"].waitForExistence(timeout: 3))
    }

    private func launchApp(fixture: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["CAPTAINS_LOG_UI_TESTING"] = "1"
        if fixture {
            app.launchEnvironment["CAPTAINS_LOG_UI_FIXTURE"] = "1"
        }
        app.launch()
        return app
    }

    private var fixtureShowcaseDayTitle: String {
        let calendar = Calendar.current
        let showcaseDate = calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        return showcaseDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func actionRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let identifier = "actionRow.\(title)"
        let button = app.buttons[identifier]
        if button.exists {
            return button
        }
        let element = app.otherElements[identifier]
        if element.exists {
            return element
        }
        return app.buttons[title]
    }
}
