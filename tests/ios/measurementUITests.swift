import XCTest

@MainActor
final class MeasurementUITests: XCTestCase {
    func testWindowAndAncestorLayoutUseRealUIKitGeometry() {
        let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonMeasurement")
        app.terminate()
        app.launch()
        let run = app.otherElements["Run measurement"]
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        run.tap()
        let result = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "measurement ")).firstMatch
        let prefix = "measurement PASS "
        let passed = NSPredicate(format: "label BEGINSWITH %@", prefix)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: passed, evaluatedWith: result)], timeout: 10), .completed, result.label)
        let values = result.label.dropFirst(prefix.count).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(values.count, 4, result.label)
        guard values.count == 4 else { app.terminate(); return }
        let anchor = app.otherElements["measurement-anchor"]
        XCTAssertTrue(anchor.exists)
        let frame = anchor.frame
        XCTAssertEqual(values[0], Double(frame.origin.x), accuracy: 0.1)
        XCTAssertEqual(values[1], Double(frame.origin.y), accuracy: 0.1)
        XCTAssertEqual(values[2], Double(frame.size.width), accuracy: 0.1)
        XCTAssertEqual(values[3], Double(frame.size.height), accuracy: 0.1)
        app.terminate()
    }
}
