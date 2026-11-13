import XCTest

final class ScanUITests: XCTestCase {
    func testModeSwitchingAndGaussianArchive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appLanguage", "system"]
        app.launch()
        let gaussian = app.segmentedControls.buttons["Gaussian Splatting"]
        XCTAssertTrue(gaussian.waitForExistence(timeout: 10))
        gaussian.tap()
        XCTAssertTrue(app.staticTexts["Capture · Create · Share"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Gaussian-mode-iPhone"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Saved Scans"].tap()
        XCTAssertTrue(app.navigationBars["Gaussian Scans"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.segmentedControls.buttons["Point Cloud"].tap()
        XCTAssertTrue(app.staticTexts["LiDAR · Scene to Point Cloud"].waitForExistence(timeout: 5))
        let pointCloud = XCTAttachment(screenshot: app.screenshot())
        pointCloud.name = "Point-cloud-mode-iPhone"; pointCloud.lifetime = .keepAlways; add(pointCloud)
    }

    func testGermanLocalizationSettingsAndCredits() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-appLanguage", "system"]
        app.launch()

        let gaussian = app.segmentedControls.buttons["Gaussian Splatting"]
        XCTAssertTrue(gaussian.waitForExistence(timeout: 10))
        gaussian.tap()
        XCTAssertTrue(app.staticTexts["Aufnehmen · Berechnen · Teilen"].waitForExistence(timeout: 5))

        app.segmentedControls.buttons["Punktwolke"].tap()
        XCTAssertTrue(app.staticTexts["LiDAR · Szene als Punktwolke"].waitForExistence(timeout: 5))
        let germanMain = XCTAttachment(screenshot: app.screenshot())
        germanMain.name = "German-Point-cloud-iPhone"; germanMain.lifetime = .keepAlways; add(germanMain)

        app.buttons["Scan-Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        app.swipeUp()
        let germanSettings = XCTAttachment(screenshot: app.screenshot())
        germanSettings.name = "German-Settings-iPhone"; germanSettings.lifetime = .keepAlways; add(germanSettings)

        let creditsButton = app.buttons["Projekt & Credits"]
        XCTAssertTrue(creditsButton.waitForExistence(timeout: 5))
        creditsButton.tap()
        XCTAssertTrue(app.navigationBars["Über & Danksagung"].waitForExistence(timeout: 5))
        if !app.staticTexts["RIM-Projekt"].waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["RIM-Projekt"].waitForExistence(timeout: 5))
        let germanCredits = XCTAttachment(screenshot: app.screenshot())
        germanCredits.name = "German-Credits-iPhone"; germanCredits.lifetime = .keepAlways; add(germanCredits)
    }

    func testLiveLanguageSwitchingInSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-appLanguage", "system"]
        app.launch()

        let settingsButton = app.buttons["Scan Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.segmentedControls.buttons["Deutsch"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        app.buttons["Fertig"].tap()
        XCTAssertTrue(app.staticTexts["LiDAR · Szene als Punktwolke"].waitForExistence(timeout: 5))

        app.buttons["Scan-Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["System"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
