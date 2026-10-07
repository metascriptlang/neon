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

@MainActor
final class FlatListUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonFlatList")

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

    private func rowsInTree() -> Int {
        return app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "row ")).count
    }

    private func report(_ name: String) {
        print("NEON_IOS flatlist-\(name) pid=\(pid()) \(label(startingWith: "mounted")) \(label(startingWith: "offset ")) \(label(startingWith: "pressed ")) rows-in-tree=\(rowsInTree())")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "flatlist-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTenThousandRows() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let mounted = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "mounted ")).firstMatch
        XCTAssertTrue(mounted.waitForExistence(timeout: 30), "the list reports its mount time")
        XCTAssertTrue(onScreen("row 0"), "row 0 starts on screen")
        XCTAssertFalse(app.staticTexts["row 9999"].exists, "row 9999 is not mounted")
        XCTAssertLessThan(rowsInTree(), 400, "a window of rows, not 10000")
        let launched = pid()
        report("initial")

        for _ in 0..<3 { app.swipeUp() }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertNotEqual(label(startingWith: "offset "), "offset 0", "onScroll moved the offset")
        XCTAssertEqual(label(startingWith: "pressed "), "pressed none", "a swipe that starts on a row does not press it")
        report("swiped")

        app.staticTexts["jump 5000"].tap()
        XCTAssertTrue(app.staticTexts["row 5000"].waitForExistence(timeout: 10), "row 5000 mounts after scrollToIndex")
        XCTAssertTrue(onScreen("row 5000"), "row 5000 is on screen")
        XCTAssertFalse(app.staticTexts["row 1000"].exists, "the rows between left the window")
        XCTAssertFalse(onScreen("row 0"), "row 0 stays mounted for scroll-to-top, off screen")
        XCTAssertLessThan(rowsInTree(), 400, "still a window at row 5000")
        report("jumped")

        app.staticTexts["row 5000"].tap()
        XCTAssertTrue(app.staticTexts["pressed row 5000"].waitForExistence(timeout: 10), "the tap hits row 5000")
        report("pressed")

        app.staticTexts["row 5001"].press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts["pressed long row 5001"].waitForExistence(timeout: 10), "a held row fires onLongPress on its std timer: \(label(startingWith: "pressed "))")
        report("long-pressed")
        app.staticTexts["row 5000"].tap()
        XCTAssertTrue(app.staticTexts["pressed row 5000"].waitForExistence(timeout: 10), "the tap hits row 5000 again")

        XCUIDevice.shared.orientation = .landscapeRight
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertTrue(app.staticTexts["pressed row 5000"].waitForExistence(timeout: 10), "state survives the rotation")
        report("landscape")
        XCUIDevice.shared.orientation = .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(app.staticTexts["pressed row 5000"].waitForExistence(timeout: 10), "state survives Home and resume")
        report("resumed")

        XCTAssertEqual(launched, pid(), "rotate, Home and resume kept the same process")
    }

    func testMeasuredStickyAndInverted() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let launched = pid()
        app.staticTexts["measured rows"].tap()
        let header = app.staticTexts["header 0"]
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["item 3"].waitForExistence(timeout: 15))
        let top = header.frame.minY
        XCTAssertEqual(app.staticTexts["item 2"].frame.minY - app.staticTexts["item 1"].frame.minY, 80, accuracy: 2)
        XCTAssertEqual(app.staticTexts["item 3"].frame.minY - app.staticTexts["item 2"].frame.minY, 112, accuracy: 2)
        report("measured-initial")

        let start = app.staticTexts["item 2"].coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -110)))
        let moved = NSPredicate { [self] _, _ in
            !label(startingWith: "offset ").isEmpty && label(startingWith: "offset ") != "offset 0"
        }
        let scrolled = expectation(for: moved, evaluatedWith: app)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 10), .completed)
        XCTAssertEqual(header.frame.minY, top, accuracy: 2, "the measured header remains pinned after a drag")
        XCTAssertEqual(label(startingWith: "pressed "), "pressed none", "scrolling must cancel the row press")
        header.tap()
        XCTAssertTrue(app.staticTexts["pressed header 0"].waitForExistence(timeout: 10))
        report("measured-sticky-pressed")

        app.staticTexts["inverted rows"].tap()
        XCTAssertTrue(app.staticTexts["pressed header 0"].waitForExistence(timeout: 10), "changing inversion preserves the mounted list state")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let pull = app.staticTexts["item 3"].coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        pull.press(forDuration: 0.1, thenDragTo: pull.withOffset(CGVector(dx: 0, dy: 300)))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let visibleHeaders = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "header ")).allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertFalse(visibleHeaders.isEmpty, "an inverted sticky header is visible")
        let invertedHeader = visibleHeaders.min { $0.frame.minY < $1.frame.minY }!
        XCTAssertEqual(invertedHeader.frame.minY, top, accuracy: 2, "the inverted header is pinned at the list top")
        let selected = invertedHeader.label
        invertedHeader.tap()
        XCTAssertTrue(app.staticTexts["pressed " + selected].waitForExistence(timeout: 10), "the transformed visible header receives its press")
        XCTAssertEqual(launched, pid(), "the measured and inverted modes share one running process")
        report("inverted-sticky-pressed")

        app.staticTexts["measured rows"].tap()
        for _ in 0..<12 {
            if onScreen("List end") { break }
            app.staticTexts["measured end"].tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTAssertTrue(onScreen("item 63"), "the measured list reaches its final item without getItemLayout")
        XCTAssertTrue(onScreen("List end"), "the footer participates in the measured end")
        report("measured-end")
    }

    func testGridAndSections() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let launched = pid()
        app.staticTexts["grid"].tap()
        XCTAssertTrue(app.staticTexts["cell 5"].waitForExistence(timeout: 15), "grid mode mounts its first rows")
        let c0 = app.staticTexts["cell 0"].frame
        let c1 = app.staticTexts["cell 1"].frame
        let c2 = app.staticTexts["cell 2"].frame
        let c3 = app.staticTexts["cell 3"].frame
        XCTAssertEqual(c1.minY, c0.minY, accuracy: 2, "cell 1 shares the first row")
        XCTAssertEqual(c2.minY, c0.minY, accuracy: 2, "cell 2 shares the first row")
        XCTAssertLessThan(c0.minX, c1.minX)
        XCTAssertLessThan(c1.minX, c2.minX)
        XCTAssertEqual(c3.minY - c0.minY, 68, accuracy: 2, "64pt cells plus the 4pt columnWrapperStyle margin")
        XCTAssertEqual(c3.minX, c0.minX, accuracy: 2, "cell 3 opens the second row")
        report("grid-initial")

        app.staticTexts["cell 4"].tap()
        XCTAssertTrue(app.staticTexts["pressed cell 4 at 4"].waitForExistence(timeout: 10), "the tap hits cell 4: \(label(startingWith: "pressed "))")
        app.staticTexts["prepend"].tap()
        XCTAssertTrue(app.staticTexts["cell 60"].waitForExistence(timeout: 10), "the prepended cell mounts")
        let fresh = app.staticTexts["cell 60"].frame
        XCTAssertEqual(fresh.minY, c0.minY, accuracy: 2, "cell 60 opens the first row")
        XCTAssertEqual(fresh.minX, c0.minX, accuracy: 2, "cell 60 takes the first column")
        XCTAssertEqual(app.staticTexts["cell 0"].frame.minX, c1.minX, accuracy: 2, "cell 0 moves to the second column")
        app.staticTexts["cell 4"].tap()
        XCTAssertTrue(app.staticTexts["pressed cell 4 at 5"].waitForExistence(timeout: 10), "cell 4 reads its new index: \(label(startingWith: "pressed "))")
        report("grid-prepended")

        app.staticTexts["sections"].tap()
        let first = app.staticTexts["Section 0"]
        XCTAssertTrue(first.waitForExistence(timeout: 15), "sections mode mounts")
        XCTAssertTrue(app.staticTexts["item 100"].waitForExistence(timeout: 15), "the second section mounts")
        let top = first.frame.minY
        XCTAssertLessThan(top, app.staticTexts["item 0"].frame.minY)
        XCTAssertLessThan(app.staticTexts["item 0"].frame.minY, app.staticTexts["item 1"].frame.minY)
        XCTAssertLessThan(app.staticTexts["item 1"].frame.minY, app.staticTexts["Section 1"].frame.minY)
        XCTAssertLessThan(app.staticTexts["Section 1"].frame.minY, app.staticTexts["item 100"].frame.minY)
        report("sections-initial")

        let start = app.staticTexts["item 1"].coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -60)), withVelocity: .slow, thenHoldForDuration: 0.5)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertLessThan(app.staticTexts["item 0"].frame.minY, top, "the drag scrolled item 0 under the header")
        XCTAssertEqual(first.frame.minY, top, accuracy: 2, "Section 0 stays pinned while its items scroll")
        XCTAssertEqual(label(startingWith: "pressed "), "pressed none", "scrolling must cancel the item press")
        report("sections-sticky")

        app.staticTexts["section 1"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(label(startingWith: "pressed ").hasPrefix("pressed jump waits"), "scrollToLocation reached a measured header")
        XCTAssertEqual(app.staticTexts["Section 1"].frame.minY, top, accuracy: 2, "scrollToLocation(1, 0) brings Section 1 to the list top")
        app.staticTexts["item 101"].tap()
        XCTAssertTrue(app.staticTexts["pressed Section 1 item 1"].waitForExistence(timeout: 10), "item 101 is Section 1 item 1: \(label(startingWith: "pressed "))")
        report("sections-located-pressed")
        XCTAssertEqual(launched, pid(), "the grid and section modes share one running process")
    }
}

final class ScrollMatrixUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonScrollMatrix")

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

    private func offsets() -> (Int, Int) {
        let words = label(startingWith: "x ").split(separator: " ")
        return (Int(words[1]) ?? -1, Int(words[3]) ?? -1)
    }

    private func report(_ name: String) {
        print("NEON_IOS matrix-\(name) pid=\(pid()) \(label(startingWith: "axis ")) \(label(startingWith: "x ")) \(label(startingWith: "pressed ")) \(label(startingWith: "refresh"))")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "matrix-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    func testAxisRefreshAndPress() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(app.staticTexts["axis horizontal"].waitForExistence(timeout: 15))
        let launched = pid()
        let one = app.staticTexts["card 1"], two = app.staticTexts["card 2"]
        XCTAssertEqual(two.frame.minY, one.frame.minY, accuracy: 1, "horizontal cards share a row")
        XCTAssertGreaterThan(two.frame.minX, one.frame.minX)
        report("initial")

        let start = two.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -220, dy: 0)))
        settle()
        let (x, y) = offsets()
        XCTAssertGreaterThan(x, 0, "a horizontal drag moves x")
        XCTAssertEqual(y, 0, "a horizontal drag leaves y")
        XCTAssertEqual(label(startingWith: "pressed "), "pressed none")
        let window = app.windows.firstMatch.frame
        let visible = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "card ")).allElementsBoundByIndex
            .filter { window.contains($0.frame) }.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertFalse(visible.isEmpty)
        let target = visible[0].label
        visible[0].tap()
        XCTAssertTrue(app.staticTexts["pressed " + target].waitForExistence(timeout: 10))
        report("horizontal")

        app.staticTexts["toggle axis"].tap()
        XCTAssertTrue(app.staticTexts["axis vertical"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["pressed " + target].exists, "the axis change keeps app state")
        settle()
        XCTAssertGreaterThan(two.frame.minY, one.frame.minY, "vertical cards stack")
        XCTAssertEqual(two.frame.minX, one.frame.minX, accuracy: 1)
        report("vertical")

        let pull = one.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        pull.press(forDuration: 0.05, thenDragTo: pull.withOffset(CGVector(dx: 0, dy: 320)))
        XCTAssertTrue(app.staticTexts["refreshed 1"].waitForExistence(timeout: 10), "pull to refresh calls onRefresh and the app's value closes it")
        report("refreshed")

        app.staticTexts["toggle axis"].tap()
        XCTAssertTrue(app.staticTexts["axis horizontal"].waitForExistence(timeout: 10))
        settle()
        XCTAssertEqual(two.frame.minY, one.frame.minY, accuracy: 1, "cards return to one row")
        XCTAssertTrue(app.staticTexts["refreshed 1"].exists)
        XCTAssertEqual(launched, pid())
        report("horizontal-again")
    }

    private func keyboard(_ shown: Bool) {
        let want = "keyboard " + (shown ? "shown" : "hidden")
        let predicate = NSPredicate { [self] _, _ in label(startingWith: "keyboard ").hasPrefix(want) && app.keyboards.count == (shown ? 1 : 0) }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: app)], timeout: 10), .completed,
            "expected \(want); app says \(label(startingWith: "keyboard ")), keyboards \(app.keyboards.count)")
    }

    func testKeyboardModes() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["axis horizontal"].waitForExistence(timeout: 15))
        app.staticTexts["toggle axis"].tap()
        XCTAssertTrue(app.staticTexts["axis vertical"].waitForExistence(timeout: 10))
        let input = app.textFields.firstMatch
        let one = app.staticTexts["card 1"]

        input.tap()
        keyboard(true)
        XCTAssertTrue(label(startingWith: "keyboard ").hasSuffix("focus yes"))
        report("keyboard-shown")
        let start = one.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)))
        keyboard(false)
        report("keyboard-dragged")

        let pull = one.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        pull.press(forDuration: 0.05, thenDragTo: pull.withOffset(CGVector(dx: 0, dy: 200)))
        settle()
        let before = label(startingWith: "pressed ")
        input.tap()
        keyboard(true)
        one.tap()
        keyboard(false)
        XCTAssertEqual(label(startingWith: "pressed "), before, "with never, the first tap only dismisses the keyboard")
        report("taps-never")

        app.staticTexts["taps never"].tap()
        XCTAssertTrue(app.staticTexts["taps always"].waitForExistence(timeout: 10))
        input.tap()
        keyboard(true)
        one.tap()
        XCTAssertTrue(app.staticTexts["pressed card 1"].waitForExistence(timeout: 10))
        keyboard(true)
        report("taps-always")

        app.staticTexts["dismiss on-drag"].tap()
        XCTAssertTrue(app.staticTexts["dismiss none"].waitForExistence(timeout: 10))
        keyboard(true)
        let again = one.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        again.press(forDuration: 0.05, thenDragTo: again.withOffset(CGVector(dx: 0, dy: -120)))
        settle()
        keyboard(true)
        report("dismiss-none")
    }
}
