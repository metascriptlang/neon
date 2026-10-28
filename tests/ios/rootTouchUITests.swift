import XCTest

@MainActor
final class RootTouchUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonRootTouch")

    override func setUp() {
        continueAfterFailure = false
        app.terminate()
        app.launch()
    }

    func testCaptureBeforeNativeSwitch() {
        let status = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "grants ")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let captured = app.switches["captured-switch"]
        XCTAssertTrue(captured.waitForExistence(timeout: 10))
        captured.tap()
        let capturedChanged = NSPredicate(format: "label == %@", "grants 1 releases 1 captured 1 plain 0")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: capturedChanged, evaluatedWith: status)], timeout: 5), .completed, status.label)
        let plain = app.switches["plain-switch"]
        XCTAssertTrue(plain.waitForExistence(timeout: 10))
        plain.tap()
        let plainChanged = NSPredicate(format: "label == %@", "grants 1 releases 1 captured 1 plain 1")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: plainChanged, evaluatedWith: status)], timeout: 5), .completed, status.label)
        app.terminate()
    }

    private var routes: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "press ")).firstMatch
    }

    private func waitRoutes(_ prefix: String) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: routes)], timeout: 5), .completed, routes.label)
    }

    func testPressChildHitSlopAndTransform() {
        let target = app.buttons["root-press"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        waitRoutes("press 1 in 1 out 1 inner 0 outer 0")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: -10, dy: 0)).tap()
        waitRoutes("press 2 in 2 out 2 inner 0 outer 0")
    }

    func testNestedTextOwnsOnePress() {
        let label = app.staticTexts["inner outer"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        label.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 14, dy: 0)).tap()
        waitRoutes("press 0 in 0 out 0 inner 1 outer 0")
        label.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -14, dy: 0)).tap()
        waitRoutes("press 0 in 0 out 0 inner 1 outer 1")
    }

    func testUnmountDuringTouchDropsStaleCallbacks() {
        let target = app.otherElements["cleanup-target"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        target.tap()
        XCTAssertTrue(target.waitForNonExistence(timeout: 5))
        let status = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "cleanupStart ")).firstMatch
        XCTAssertEqual(status.label, "cleanupStart 1 end 0")
        app.buttons["restore-target"].tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        XCTAssertTrue(target.waitForNonExistence(timeout: 5))
        XCTAssertEqual(status.label, "cleanupStart 2 end 0")
        app.buttons["root-press"].tap()
        waitRoutes("press 1 in 1 out 1 inner 0 outer 0")
    }

    func testCancellationDoesNotResurrectRoot() {
        let target = app.otherElements["cancel-target"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 30, dy: 0)))
        let status = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "cancelStart ")).firstMatch
        XCTAssertEqual(status.label, "cancelStart 1 cancel 1 end 0")
        app.buttons["root-press"].tap()
        waitRoutes("press 1 in 1 out 1 inner 0 outer 0")
    }

    private func scrollPressThenHold(_ hold: TimeInterval) {
        let target = app.buttons["scroll-press"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)),
                    withVelocity: .fast, thenHoldForDuration: hold)
        let status = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "scrollPress ")).firstMatch
        let cancelled = NSPredicate(format: "label == %@", "scrollPress 0 in 1 long 0 out 1")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: cancelled, evaluatedWith: status)], timeout: 5), .completed, status.label)
        XCTAssertTrue(routes.label.contains("scrollStart 1"), routes.label)
        XCTAssertTrue(routes.label.hasSuffix("scrollEnd 1"), routes.label)
        XCTAssertFalse(routes.label.contains("scrollMove 0 "), routes.label)
        app.buttons["root-press"].tap()
        waitRoutes("press 1 in 1 out 1 inner 0 outer 0")
    }

    func testScrollTakeoverCancelsPressAndKeepsRawLifecycle() {
        scrollPressThenHold(0)
    }

    func testScrollTakeoverCancelsLongTimerWhileTouchRemainsDown() {
        scrollPressThenHold(0.8)
    }

    func testScrollReportsOneLifecycle() {
        let first = app.staticTexts["scroll first"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let before = first.frame.minY
        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -110)))
        let predicate = NSPredicate(format: "label CONTAINS %@", "scrollStart 1")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: routes)], timeout: 5), .completed, routes.label)
        XCTAssertTrue(routes.label.hasSuffix("scrollEnd 1"), routes.label)
        XCTAssertFalse(routes.label.contains("scrollMove 0 "), routes.label)
        XCTAssertLessThan(first.frame.minY, before - 30, "the native scroll view remains active")
    }
}
