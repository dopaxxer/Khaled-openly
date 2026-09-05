import XCTest
final class OpenlyUITests:XCTestCase {
 func testEnglishLoginAndKeyboardDismissal(){let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"];app.launch();XCTAssertTrue(app.staticTexts["Welcome back."].waitForExistence(timeout:10));let email=app.textFields["Email"];XCTAssertTrue(email.exists);email.tap();email.typeText("ui-test@example.test");let done=app.buttons["Done"];if done.exists{done.tap()};XCTAssertTrue(app.buttons["Create an account"].isHittable)}
 func testArabicRegistrationSurface(){let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ar)","-AppleLocale","ar_SA"];app.launch();XCTAssertTrue(app.buttons["إنشاء حساب"].waitForExistence(timeout:10));app.buttons["إنشاء حساب"].tap();XCTAssertTrue(app.textFields["اسم المستخدم"].exists)}
}
