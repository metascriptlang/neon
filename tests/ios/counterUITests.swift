import XCTest

@MainActor
final class CounterUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonCounter")

    // iPhone 17 Pro safe areas, the device tests/ios/run.sh creates.
    private let portraitSafe = CGRect(x: 0, y: 62, width: 402, height: 778)
    private let landscapeSafe = CGRect(x: 62, y: 0, width: 750, height: 382)

    override func setUp() {
        continueAfterFailure = false
    }

    private func pid() -> String {
        let text = app.debugDescription
        guard let range = text.range(of: "pid: ") else { return "" }
        return String(text[range.upperBound...].prefix(while: { $0.isNumber }))
    }

    private func rotate(_ orientation: UIDeviceOrientation, landscape: Bool) {
        XCUIDevice.shared.orientation = orientation
        let title = app.staticTexts["Neon Counter"]
        let deadline = Date().addingTimeInterval(20)
        var previous = CGRect.null
        while Date() < deadline {
            let window = app.windows.firstMatch.frame
            let frame = title.exists ? title.frame : .null
            if (window.width > window.height) == landscape && frame == previous && !frame.isNull { return }
            previous = frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("window did not settle in \(landscape ? "landscape" : "portrait"): \(app.windows.firstMatch.frame)")
    }

    private func check(_ name: String, value: String, parity: String) {
        let window = app.windows.firstMatch.frame
        let landscape = window.width > window.height
        XCTAssertEqual(window.size, landscape ? CGSize(width: 874, height: 402) : CGSize(width: 402, height: 874))
        let safe = landscape ? landscapeSafe : portraitSafe
        for label in ["Neon Counter", value, "-", "reset", "+", parity] {
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 10), "\(name): no static text \(label)")
        }
        let texts = app.staticTexts.allElementsBoundByIndex
        for text in texts {
            XCTAssertTrue(safe.contains(text.frame), "\(name): \(text.label) at \(text.frame) outside safe area \(safe)")
        }
        print("NEON_IOS \(name) pid=\(pid()) window=\(window) texts=\(texts.map { "\($0.label)@\($0.frame)" })")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func press(_ label: String) {
        app.staticTexts[label].tap()
    }

    func testRotateAndPress() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        rotate(.portrait, landscape: false)
        let launched = pid()
        check("portrait-initial", value: "0", parity: "even")

        rotate(.landscapeRight, landscape: true)
        check("landscape", value: "0", parity: "even")
        press("+")
        check("landscape-pressed", value: "1", parity: "odd")

        rotate(.portrait, landscape: false)
        check("portrait-returned", value: "1", parity: "odd")
        press("+")
        check("portrait-pressed", value: "2", parity: "even")

        XCTAssertEqual(launched, pid(), "rotation relaunched the app")
    }
}

@MainActor
final class ListUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonList")

    override func setUp() {
        continueAfterFailure = false
    }

    private func pid() -> String {
        let text = app.debugDescription
        guard let range = text.range(of: "pid: ") else { return "" }
        return String(text[range.upperBound...].prefix(while: { $0.isNumber }))
    }

    private func label(startingWith prefix: String) -> String {
        let match = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        return match.exists ? match.label : ""
    }

    private func onScreen(_ label: String) -> Bool {
        let text = app.staticTexts[label]
        return text.exists && app.windows.firstMatch.frame.contains(text.frame)
    }

    private func report(_ name: String) {
        print("NEON_IOS list-\(name) pid=\(pid()) window=\(app.windows.firstMatch.frame) \(label(startingWith: "offset ")) \(label(startingWith: "pressed "))")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "list-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testScrollPressRotateResume() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(app.staticTexts["offset 0"].waitForExistence(timeout: 20), "initial offset")
        XCTAssertTrue(onScreen("row 1"), "row 1 starts on screen")
        XCTAssertFalse(onScreen("row 30"), "row 30 starts below the fold")
        let launched = pid()
        report("initial")

        var swipes = 0
        while !onScreen("row 30") && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(onScreen("row 30"), "row 30 scrolled into view after \(swipes) swipes")
        XCTAssertNotEqual(label(startingWith: "offset "), "offset 0", "onScroll moved the offset")
        XCTAssertEqual(label(startingWith: "pressed "), "pressed none", "a swipe that starts on a row does not press it")
        report("scrolled")

        app.staticTexts["row 30"].tap()
        XCTAssertTrue(app.staticTexts["pressed row 30"].waitForExistence(timeout: 10), "the tap after scrolling hits row 30")
        report("pressed")

        XCUIDevice.shared.orientation = .landscapeRight
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertTrue(app.staticTexts["pressed row 30"].waitForExistence(timeout: 10), "state survives the rotation")
        report("landscape")
        XCUIDevice.shared.orientation = .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(app.staticTexts["pressed row 30"].waitForExistence(timeout: 10), "state survives Home and resume")
        report("resumed")

        XCTAssertEqual(launched, pid(), "rotate, Home and resume kept the same process")
    }
}
