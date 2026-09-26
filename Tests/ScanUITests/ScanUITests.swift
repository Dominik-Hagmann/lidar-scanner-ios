import XCTest

final class ScanUITests: XCTestCase {
    func testModeSwitchingAndGaussianArchive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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
}
