import XCTest

final class WhackBotVisualChecks: XCTestCase {
    @MainActor func testModeAndHolePresentation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.verabot.app")
        app.activate()
        let playground = app.tabBars.buttons["游乐场"]
        XCTAssertTrue(playground.waitForExistence(timeout: 15))
        playground.tap()
        let gameEntry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打地鼠")).firstMatch
        XCTAssertTrue(gameEntry.waitForExistence(timeout: 10))
        gameEntry.tap()
        let primary = app.buttons["whack-bot-primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        capture(app, "normal-ready")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "点中小 Bot +10 分")).firstMatch.exists)
        let mode = app.segmentedControls["whack-bot-mode"]
        XCTAssertTrue(mode.exists)
        mode.buttons["困难模式"].tap()
        capture(app, "hard-ready")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "最低 0 分")).firstMatch.exists)
        primary.tap()
        XCTAssertFalse(mode.isEnabled)
        capture(app, "hard-running")
        primary.tap()
        XCTAssertEqual(primary.label, "继续")
        XCTAssertTrue(app.staticTexts["休息一下"].exists)
        capture(app, "hard-paused")
        app.buttons["玩法"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "困难模式按本局结束时的得分记录")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
