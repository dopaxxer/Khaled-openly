import XCTest

final class InteractionTests: XCTestCase {
    private func launch(_ language: String = "en") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--openly-ui-fixture", "-openly.language", language, "-openly.appearance", "light", "-openly.colorTheme", "graphite"]
        app.launch()
        XCTAssertTrue(app.buttons["home.write"].waitForExistence(timeout: 15))
        return app
    }

    func testMusicFailureRetryAndKeyboardDismissal() {
        let app = launch()
        app.buttons["home.write"].tap()
        app.buttons["Add a song"].tap()
        let query = app.textFields["music.search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap(); query.typeText("blue")
        XCTAssertTrue(app.staticTexts["music.search.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["music.search.empty"].exists)
        app.buttons["music.search.retry"].tap()
        XCTAssertTrue(app.staticTexts["BLUE"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["music.search.error"].exists)
        app.buttons["keyboard.dismiss"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))
        screenshot(app, "music-recovered-en")
        app.buttons["music.search.clear"].tap()
        XCTAssertFalse(app.staticTexts["BLUE"].exists)
        app.buttons["music.search.close"].tap()
        XCTAssertTrue(app.buttons["composer.close"].waitForExistence(timeout: 3))
        app.buttons["composer.close"].tap()
        XCTAssertTrue(app.buttons["home.write"].waitForExistence(timeout: 3))
    }

    func testComposerCanCloseWithKeyboardVisible() {
        let app = launch()
        app.buttons["home.write"].tap()
        let field = app.textViews["composer.body"].exists ? app.textViews["composer.body"] : app.textFields["composer.body"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("A new thought")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["composer.close"].tap()
        XCTAssertTrue(app.buttons["home.write"].waitForExistence(timeout: 3))
    }

    func testMessagesKeepNewDraftWhileSending() {
        let app = launch()
        app.tabBars.buttons["Messages"].tap()
        app.staticTexts["BLUE"].tap()
        let field = app.textViews["message.composer"].exists ? app.textViews["message.composer"] : app.textFields["message.composer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("First message")
        app.buttons["message.send"].tap()
        field.typeText("Next draft")
        XCTAssertTrue(app.staticTexts["First message"].waitForExistence(timeout: 5))
        let sent = app.images["message.sent"]
        XCTAssertTrue(sent.waitForExistence(timeout: 6))
        XCTAssertEqual(field.value as? String, "Next draft")
        app.buttons["keyboard.dismiss"].tap()
        screenshot(app, "messages-en")
    }

    func testArabicNavigationAndNotifications() {
        let app = launch("ar")
        XCTAssertTrue(app.tabBars.buttons["الرسائل"].exists)
        XCTAssertTrue(app.tabBars.buttons["الإشعارات"].exists)
        screenshot(app, "home-ar")
        app.tabBars.buttons["الإشعارات"].tap()
        XCTAssertTrue(app.staticTexts["أعجب BLUE بمنشورك"].waitForExistence(timeout: 5))
        screenshot(app, "notifications-ar")
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
