import XCTest

/// Launch real UI in both interface directions; screenshots remain in xcresult.
/// Authentication/publishing still need a provisioned device and a test account.
final class LaunchTests: XCTestCase {
    func testArabicLightLogin() throws { try verifyLogin(language: "ar", appearance: "light") }
    func testEnglishDarkLogin() throws { try verifyLogin(language: "en", appearance: "dark") }

    private func verifyLogin(language: String, appearance: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-openly.language", language, "-openly.appearance", appearance, "-openly.colorTheme", "graphite"]
        app.launch()
        let title = app.staticTexts["login.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 65), "Native sign-in screen did not appear")
        XCTAssertTrue(title.isHittable, "Sign-in heading is clipped or hidden")
        XCTAssertEqual(title.label, language == "ar" ? "مرحبًا بك في Openly" : "Welcome to openly")
        let continueButton = app.buttons["login.continue"]
        if continueButton.waitForExistence(timeout: 10) {
            XCTAssertEqual(continueButton.label, language == "ar" ? "متابعة" : "Continue")
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "login-\(language)-\(appearance)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
    }
}
