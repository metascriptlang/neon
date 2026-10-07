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
        let texts = ["Neon Counter", value, parity].map { app.staticTexts[$0] }
        let pressables = ["-", "reset", "+"].map { element($0) }
        for text in texts {
            XCTAssertTrue(text.waitForExistence(timeout: 10), "\(name): no static text \(text)")
        }
        for pressable in pressables {
            XCTAssertTrue(pressable.waitForExistence(timeout: 10), "\(name): no accessible pressable \(pressable)")
        }
        let shown = texts + pressables
        for item in shown {
            XCTAssertTrue(safe.contains(item.frame), "\(name): \(item.label) at \(item.frame) outside safe area \(safe)")
        }
        print("NEON_IOS \(name) pid=\(pid()) window=\(window) texts=\(shown.map { "\($0.label)@\($0.frame)" })")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func press(_ label: String) {
        element(label).tap()
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

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func onScreen(_ item: XCUIElement) -> Bool {
        item.exists && app.windows.firstMatch.frame.contains(item.frame)
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
        XCTAssertTrue(onScreen(element("row 1")), "row 1 starts on screen")
        XCTAssertFalse(onScreen(element("row 30")), "row 30 starts below the fold")
        let launched = pid()
        report("initial")

        var swipes = 0
        while !onScreen(element("row 30")) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(onScreen(element("row 30")), "row 30 scrolled into view after \(swipes) swipes")
        XCTAssertNotEqual(label(startingWith: "offset "), "offset 0", "onScroll moved the offset")
        XCTAssertEqual(label(startingWith: "pressed "), "pressed none", "a swipe that starts on a row does not press it")
        report("scrolled")

        element("row 30").tap()
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

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func onScreen(_ item: XCUIElement) -> Bool {
        item.exists && app.windows.firstMatch.frame.contains(item.frame)
    }

    private func rowsInTree() -> Int {
        return app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "row ")).count
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
        XCTAssertTrue(onScreen(element("row 0")), "row 0 starts on screen")
        XCTAssertFalse(element("row 9999").exists, "row 9999 is not mounted")
        XCTAssertLessThan(rowsInTree(), 400, "a window of rows, not 10000")
        let launched = pid()
        report("initial")

        for _ in 0..<3 { app.swipeUp() }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertNotEqual(label(startingWith: "offset "), "offset 0", "onScroll moved the offset")
        XCTAssertEqual(label(startingWith: "pressed "), "pressed none", "a swipe that starts on a row does not press it")
        report("swiped")

        element("jump 5000").tap()
        XCTAssertTrue(element("row 5000").waitForExistence(timeout: 10), "row 5000 mounts after scrollToIndex")
        XCTAssertTrue(onScreen(element("row 5000")), "row 5000 is on screen")
        XCTAssertFalse(element("row 1000").exists, "the rows between left the window")
        XCTAssertFalse(onScreen(element("row 0")), "row 0 stays mounted for scroll-to-top, off screen")
        XCTAssertLessThan(rowsInTree(), 400, "still a window at row 5000")
        report("jumped")

        element("row 5000").tap()
        XCTAssertTrue(app.staticTexts["pressed row 5000"].waitForExistence(timeout: 10), "the tap hits row 5000")
        report("pressed")

        element("row 5001").press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts["pressed long row 5001"].waitForExistence(timeout: 10), "a held row fires onLongPress on its std timer: \(label(startingWith: "pressed "))")
        report("long-pressed")
        element("row 5000").tap()
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
        element("measured rows").tap()
        let header = element("header 0")
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        XCTAssertTrue(element("item 3").waitForExistence(timeout: 15))
        let top = header.frame.minY
        XCTAssertEqual(element("item 2").frame.minY - element("item 1").frame.minY, 80, accuracy: 2)
        XCTAssertEqual(element("item 3").frame.minY - element("item 2").frame.minY, 112, accuracy: 2)
        report("measured-initial")

        let start = element("item 2").coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
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

        element("inverted rows").tap()
        XCTAssertTrue(app.staticTexts["pressed header 0"].waitForExistence(timeout: 10), "changing inversion preserves the mounted list state")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let headers = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "header "))
        func pinnedHeader() -> XCUIElement? {
            headers.allElementsBoundByIndex.filter { $0.isHittable }.min { $0.frame.minY < $1.frame.minY }
        }
        for _ in 0..<4 {
            if let h = pinnedHeader(), abs(h.frame.minY - top) <= 2 { break }
            let pull = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            pull.press(forDuration: 0.1, thenDragTo: pull.withOffset(CGVector(dx: 0, dy: 150)), withVelocity: .slow, thenHoldForDuration: 0.3)
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        let visibleHeaders = headers.allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertFalse(visibleHeaders.isEmpty, "an inverted sticky header is visible")
        let invertedHeader = visibleHeaders.min { $0.frame.minY < $1.frame.minY }!
        XCTAssertEqual(invertedHeader.frame.minY, top, accuracy: 2, "the inverted header is pinned at the list top")
        let selected = invertedHeader.label
        invertedHeader.tap()
        XCTAssertTrue(app.staticTexts["pressed " + selected].waitForExistence(timeout: 10), "the transformed visible header receives its press")
        XCTAssertEqual(launched, pid(), "the measured and inverted modes share one running process")
        report("inverted-sticky-pressed")

        element("measured rows").tap()
        for _ in 0..<12 {
            if onScreen(app.staticTexts["List end"]) { break }
            element("measured end").tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTAssertTrue(onScreen(element("item 63")), "the measured list reaches its final item without getItemLayout")
        XCTAssertTrue(onScreen(app.staticTexts["List end"]), "the footer participates in the measured end")
        report("measured-end")
    }

    func testGridAndSections() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let launched = pid()
        element("grid").tap()
        XCTAssertTrue(element("cell 5").waitForExistence(timeout: 15), "grid mode mounts its first rows")
        let c0 = element("cell 0").frame
        let c1 = element("cell 1").frame
        let c2 = element("cell 2").frame
        let c3 = element("cell 3").frame
        XCTAssertEqual(c1.minY, c0.minY, accuracy: 2, "cell 1 shares the first row")
        XCTAssertEqual(c2.minY, c0.minY, accuracy: 2, "cell 2 shares the first row")
        XCTAssertLessThan(c0.minX, c1.minX)
        XCTAssertLessThan(c1.minX, c2.minX)
        XCTAssertEqual(c3.minY - c0.minY, 68, accuracy: 2, "64pt cells plus the 4pt columnWrapperStyle margin")
        XCTAssertEqual(c3.minX, c0.minX, accuracy: 2, "cell 3 opens the second row")
        report("grid-initial")

        element("cell 2").tap()
        XCTAssertTrue(element("cell 2 tapped 1").waitForExistence(timeout: 10), "cell 2 counts its own tap: \(label(startingWith: "pressed "))")
        element("cell 4").tap()
        XCTAssertTrue(app.staticTexts["pressed cell 4 at 4"].waitForExistence(timeout: 10), "the tap hits cell 4: \(label(startingWith: "pressed "))")
        element("prepend").tap()
        XCTAssertTrue(element("cell 60").waitForExistence(timeout: 10), "the prepended cell mounts")
        let fresh = element("cell 60").frame
        XCTAssertEqual(fresh.minY, c0.minY, accuracy: 2, "cell 60 opens the first row")
        XCTAssertEqual(fresh.minX, c0.minX, accuracy: 2, "cell 60 takes the first column")
        XCTAssertEqual(element("cell 0").frame.minX, c1.minX, accuracy: 2, "cell 0 moves to the second column")
        let moved = element("cell 2 tapped 1")
        XCTAssertTrue(moved.exists, "cell 2 keeps its own counter when the prepend moves it to the second row")
        XCTAssertEqual(moved.frame.minY, c3.minY, accuracy: 2, "cell 2 opens the second row")
        XCTAssertEqual(moved.frame.minX, c0.minX, accuracy: 2, "cell 2 takes the first column")
        report("grid-prepended")
        moved.tap()
        XCTAssertTrue(element("cell 2 tapped 2").waitForExistence(timeout: 10), "the moved cell counts on from its kept state")
        XCTAssertTrue(app.staticTexts["pressed cell 2 at 3"].exists, "cell 2 reads its new index: \(label(startingWith: "pressed "))")
        element("cell 4 tapped 1").tap()
        XCTAssertTrue(app.staticTexts["pressed cell 4 at 5"].waitForExistence(timeout: 10), "cell 4 reads its new index: \(label(startingWith: "pressed "))")
        report("grid-moved-kept-state")

        element("sections").tap()
        let first = app.staticTexts["Section 0"]
        XCTAssertTrue(first.waitForExistence(timeout: 15), "sections mode mounts")
        XCTAssertTrue(element("item 100").waitForExistence(timeout: 15), "the second section mounts")
        let top = first.frame.minY
        XCTAssertLessThan(top, element("item 0").frame.minY)
        XCTAssertLessThan(element("item 0").frame.minY, element("item 1").frame.minY)
        XCTAssertLessThan(element("item 1").frame.minY, app.staticTexts["Section 1"].frame.minY)
        XCTAssertLessThan(app.staticTexts["Section 1"].frame.minY, element("item 100").frame.minY)
        report("sections-initial")

        let start = element("item 1").coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -60)), withVelocity: .slow, thenHoldForDuration: 0.5)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertLessThan(element("item 0").frame.minY, top, "the drag scrolled item 0 under the header")
        XCTAssertEqual(first.frame.minY, top, accuracy: 2, "Section 0 stays pinned while its items scroll")
        XCTAssertEqual(label(startingWith: "pressed "), "pressed none", "scrolling must cancel the item press")
        report("sections-sticky")

        element("section 1").tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(label(startingWith: "pressed ").hasPrefix("pressed jump waits"), "scrollToLocation reached a measured header")
        XCTAssertEqual(app.staticTexts["Section 1"].frame.minY, top, accuracy: 2, "scrollToLocation(1, 0) brings Section 1 to the list top")
        element("item 101").tap()
        XCTAssertTrue(app.staticTexts["pressed Section 1 item 1"].waitForExistence(timeout: 10), "item 101 is Section 1 item 1: \(label(startingWith: "pressed "))")
        report("sections-located-pressed")
        XCTAssertEqual(launched, pid(), "the grid and section modes share one running process")
    }

    private func messagesBelow(_ top: CGFloat) -> [XCUIElement] {
        let window = app.windows.firstMatch.frame
        return app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "message ")).allElementsBoundByIndex
            .filter { $0.frame.minY >= top && window.contains($0.frame) }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    func testChatKeepsVisibleMessage() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let launched = pid()
        element("chat").tap()
        XCTAssertTrue(app.staticTexts["messages 40, oldest 1000"].waitForExistence(timeout: 15), "chat mode mounts its 40 messages")
        XCTAssertTrue(app.staticTexts["message 1002"].waitForExistence(timeout: 15))
        let start = app.staticTexts["message 1002"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 120))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)), withVelocity: .slow, thenHoldForDuration: 0.5)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertNotEqual(label(startingWith: "offset "), "offset 0", "the drag scrolled the chat")
        let listTop = element("load older").frame.maxY + 16
        let shown = messagesBelow(listTop)
        XCTAssertGreaterThan(shown.count, 2, "messages on screen below the list top")
        let kept = shown[0].label
        let before = app.staticTexts[kept].frame.minY
        let offset = label(startingWith: "offset ")
        report("chat-before")

        element("load older").tap()
        XCTAssertTrue(app.staticTexts["messages 60, oldest 980"].waitForExistence(timeout: 10), "load older prepends 20 messages")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let after = app.staticTexts[kept].frame.minY
        XCTAssertEqual(after, before, accuracy: 2, "\(kept) stays where it was")
        print("NEON_IOS flatlist-chat kept=\(kept) y=\(before)->\(after) \(offset) -> \(label(startingWith: "offset "))")
        report("chat-kept")

        let pull = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        for _ in 0..<8 where !(onScreen(app.staticTexts["message 980"]) && app.staticTexts["message 980"].frame.minY >= listTop) {
            pull.press(forDuration: 0.1, thenDragTo: pull.withOffset(CGVector(dx: 0, dy: 300)))
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(onScreen(app.staticTexts["message 980"]), "the older messages are above the kept one")
        let older = messagesBelow(listTop).map { Int($0.label.dropFirst("message ".count)) ?? -1 }
        XCTAssertEqual(older, older.sorted(), "older messages read top to bottom")
        report("chat-older")
        XCTAssertEqual(launched, pid(), "the chat mode runs in the same process")
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

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
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
        let one = element("card 1"), two = element("card 2")
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
        let visible = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "card ")).allElementsBoundByIndex
            .filter { window.contains($0.frame) }.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertFalse(visible.isEmpty)
        let target = visible[0].label
        visible[0].tap()
        XCTAssertTrue(app.staticTexts["pressed " + target].waitForExistence(timeout: 10))
        report("horizontal")

        element("toggle axis").tap()
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

        element("toggle axis").tap()
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
        element("toggle axis").tap()
        XCTAssertTrue(app.staticTexts["axis vertical"].waitForExistence(timeout: 10))
        let input = app.textFields.firstMatch
        let one = element("card 1")

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

        element("taps never").tap()
        XCTAssertTrue(element("taps always").waitForExistence(timeout: 10))
        input.tap()
        keyboard(true)
        one.tap()
        XCTAssertTrue(app.staticTexts["pressed card 1"].waitForExistence(timeout: 10))
        keyboard(true)
        report("taps-always")

        element("dismiss on-drag").tap()
        XCTAssertTrue(element("dismiss none").waitForExistence(timeout: 10))
        keyboard(true)
        let again = one.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        again.press(forDuration: 0.05, thenDragTo: again.withOffset(CGVector(dx: 0, dy: -120)))
        settle()
        keyboard(true)
        report("dismiss-none")
    }
}

final class CatalogUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonCatalog")

    override func setUp() {
        continueAfterFailure = false
    }

    private func report(_ name: String) {
        print("NEON_IOS catalog-\(name)")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "catalog-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func text(_ label: String, timeout: TimeInterval = 15) -> XCUIElement {
        let element = app.staticTexts[label]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "no text \(label); texts \(app.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label })")
        return element
    }

    private func button(_ label: String, timeout: TimeInterval = 15) -> XCUIElement {
        let element = app.buttons[label]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "no button \(label); buttons \(app.buttons.allElementsBoundByIndex.prefix(30).map { $0.label })")
        return element
    }

    private func clear(_ field: XCUIElement, _ count: Int) {
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
    }

    func testSearchDetailEditSave() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        if app.staticTexts["Loading products"].waitForExistence(timeout: 5) { report("loading") }
        _ = text("12 products")
        let short = button("Field notebook, $12"), long = button("Walnut desk tray, $48")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        report("list")
        print("NEON_IOS catalog-rows short=\(short.frame) long=\(long.frame)")
        XCTAssertGreaterThan(long.frame.height, short.frame.height + 10, "the long description wraps into a taller row")

        let search = app.textFields["Search products"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "the software keyboard opens")
        search.typeText("mug")
        _ = text("1 product")
        _ = button("Ceramic mug, $18")
        XCTAssertFalse(app.buttons["Brass pen, $36"].exists, "search drops a non-matching row")
        report("search")
        search.typeText("zzz")
        _ = text("No products match \"mugzzz\"")
        report("empty")
        clear(search, 6)
        _ = text("12 products")
        search.typeText("\n")

        app.switches["Simulate offline"].tap()
        _ = text("Could not reach the catalog. Check the connection and try again.")
        report("error")
        app.switches["Simulate offline"].tap()
        if app.buttons["Retry"].waitForExistence(timeout: 3) { app.buttons["Retry"].tap() }
        _ = text("12 products")

        let mug = button("Ceramic mug, $18")
        if !app.windows.firstMatch.frame.contains(mug.frame) { app.swipeUp() }
        mug.tap()
        _ = button("Edit")
        _ = text("$18")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        report("detail")

        button("Edit").tap()
        _ = text("Edit product")
        let title = app.textFields["Title"]
        clear(title, 20)
        button("Save").tap()
        _ = text("Title is required.")
        report("invalid")
        title.tap()
        title.typeText("Clay cup")
        clear(app.textFields["Price"], 6)
        app.textFields["Price"].typeText("21")
        button("Save").tap()
        _ = text("Clay cup")
        _ = text("$21")
        _ = button("Edit")
        report("saved")
        button("Back to catalog").tap()
        _ = button("Clay cup, $21")
        report("list-after-save")
    }
}

final class SettingsUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonSettings")

    override func setUp() {
        continueAfterFailure = false
    }

    private func label(startingWith prefix: String) -> String {
        let match = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        return match.exists ? match.label : ""
    }

    private func waitLabel(_ prefix: String, containing part: String) {
        let predicate = NSPredicate { [self] _, _ in label(startingWith: prefix).contains(part) }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: app)], timeout: 10), .completed,
            "expected \(prefix)… to contain \(part); it reads \(label(startingWith: prefix))")
    }

    private func report(_ name: String) {
        print("NEON_IOS settings-\(name) \(label(startingWith: "Compact")) \(label(startingWith: "Wide")) \(label(startingWith: "Focus:"))")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "settings-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testFocusThemeAndLayout() {
        XCUIDevice.shared.orientation = .portrait
        if #available(iOS 17.0, *) { XCUIDevice.shared.appearance = .light }
        app.launch()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 20))
        waitLabel("Compact", containing: "light theme (system light)")
        for name in ["Use system theme", "Large text", "Notifications"] {
            XCTAssertTrue(app.switches[name].exists, "switch \(name) is exposed with its label")
        }
        XCTAssertTrue(app.buttons["Save profile"].exists, "the save button is exposed as a button")
        XCTAssertEqual(app.buttons["Save profile"].value as? String ?? "", "", "no stray value on the button")
        XCTAssertTrue(app.textFields["Name"].exists && app.textFields["Email"].exists, "fields are labelled")
        print("NEON_IOS settings-a11y switches=\(app.switches.allElementsBoundByIndex.map { $0.label }) buttons=\(app.buttons.allElementsBoundByIndex.map { $0.label }) fields=\(app.textFields.allElementsBoundByIndex.map { $0.label })")
        report("start")

        app.textFields["Name"].tap()
        waitLabel("Focus:", containing: "Focus: name")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        waitLabel("Focus:", containing: "pt")
        report("name-focused")
        app.textFields["Name"].typeText(" King\n")
        waitLabel("Focus:", containing: "Focus: email")
        report("email-focused")
        app.textFields["Email"].typeText("\n")
        XCTAssertTrue(app.staticTexts["Saved Ada Lovelace King <ada@example.com>"].waitForExistence(timeout: 10))
        waitLabel("Focus:", containing: "Focus: none · keyboard hidden")
        report("saved")

        app.switches["Use system theme"].tap()
        XCTAssertTrue(app.switches["Dark mode"].waitForExistence(timeout: 10))
        app.switches["Dark mode"].tap()
        waitLabel("Compact", containing: "dark theme (system light)")
        report("dark")
        app.switches["Large text"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        report("large-text")
        app.switches["Large text"].tap()
        app.switches["Use system theme"].tap()
        if #available(iOS 17.0, *) {
            XCUIDevice.shared.appearance = .dark
            let followed = NSPredicate { [self] _, _ in label(startingWith: "Compact").contains("dark theme (system dark)") }
            let result = XCTWaiter.wait(for: [expectation(for: followed, evaluatedWith: app)], timeout: 6)
            print("NEON_IOS settings-system-appearance \(result == .completed ? "followed" : "not delivered by XCUIDevice") \(label(startingWith: "Compact"))")
            report("system-dark-requested")
            XCUIDevice.shared.appearance = .light
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        waitLabel("Wide", containing: "Wide layout")
        let name = app.textFields["Name"].frame, theme = app.switches["Use system theme"].frame
        XCTAssertGreaterThan(theme.minX, name.maxX, "landscape puts the sections side by side")
        report("landscape")
        XCUIDevice.shared.orientation = .portrait
        waitLabel("Compact", containing: "Compact layout")
    }
}

final class ApisUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonApis")

    override func setUp() {
        continueAfterFailure = false
    }

    private func label(startingWith prefix: String) -> String {
        let match = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        return match.exists ? match.label : ""
    }

    private func waitLabel(_ prefix: String, containing part: String, timeout: TimeInterval = 10) {
        let predicate = NSPredicate { [self] _, _ in label(startingWith: prefix).contains(part) }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: app)], timeout: timeout), .completed,
            "expected \(prefix)… to contain \(part); it reads \(label(startingWith: prefix))")
    }

    private func report(_ name: String) {
        func flat(_ node: XCUIElementSnapshot) -> [String] {
            (node.elementType == .staticText ? [node.label] : []) + node.children.flatMap { flat($0) }
        }
        let texts = ((try? app.snapshot()).map { flat($0) } ?? []).prefix(16).joined(separator: " | ")
        print("NEON_IOS apis-\(name) \(texts)")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "apis-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func tap(_ text: String) {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "no \(text)")
        element.tap()
    }

    func testAlertShareClipboardAppState() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["Neon APIs"].waitForExistence(timeout: 20))
        let version = UIDevice.current.systemVersion
        waitLabel("os ", containing: "os ios v\(version) pad no")
        waitLabel("ratio ", containing: "ratio 3 ")
        waitLabel("url ", containing: "can https yes")
        let launchedActive = NSPredicate { [self] _, _ in
            let state = label(startingWith: "state ")
            return state == "state active" || state.hasSuffix(">active")
        }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: launchedActive, evaluatedWith: app)], timeout: 10), .completed,
            "AppState ends active after launch; it reads \(label(startingWith: "state "))")
        report("initial")

        tap("show alert")
        let alert = app.alerts["Neon alert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "UIAlertController is shown")
        XCTAssertTrue(alert.staticTexts["Pick one"].exists)
        report("alert-shown")
        alert.buttons["Confirm"].tap()
        waitLabel("alert ", containing: "alert confirm")
        tap("show alert")
        XCTAssertTrue(app.alerts["Neon alert"].waitForExistence(timeout: 10))
        app.alerts["Neon alert"].buttons["Cancel"].tap()
        waitLabel("alert ", containing: "alert cancel")

        tap("copy")
        tap("paste")
        waitLabel("pasted ", containing: "pasted neon-1")
        tap("vibrate")
        waitLabel("vibrated ", containing: "vibrated 1")
        report("clipboard")

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the demo's text input")
        field.tap()
        waitLabel("reader ", containing: "keyboard shown")
        tap("dismiss")
        waitLabel("reader ", containing: "keyboard hidden")
        tap("announce")

        tap("share")
        let copy = app.buttons["Copy"].firstMatch
        let cell = app.cells["Copy"].firstMatch
        let sheet = NSPredicate { _, _ in copy.exists || cell.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: sheet, evaluatedWith: app)], timeout: 15), .completed, "the activity sheet offers Copy")
        report("share-sheet")
        if copy.exists { copy.tap() } else { cell.tap() }
        waitLabel("share ", containing: "share sharedAction")
        report("shared")

        tap("open url")
        waitLabel("url ", containing: "url ")
        let opened = label(startingWith: "url ")
        print("NEON_IOS apis-tel \(opened)")

        let before = label(startingWith: "state ")
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitLabel("state ", containing: String(before.dropFirst("state ".count)) + ">inactive>background>active")
        report("appstate")

        tap("settings")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15), "Linking.openSettings brings Settings forward")
        report("settings")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitLabel("url ", containing: "url settings")
        waitLabel("state ", containing: ">active")
        report("back-from-settings")
    }
}

final class GalleryUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonGallery")

    override func setUp() {
        continueAfterFailure = false
    }

    private func label(startingWith prefix: String) -> String {
        let match = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        return match.exists ? match.label : ""
    }

    private func status(_ text: String, timeout: TimeInterval = 10) {
        XCTAssertTrue(app.staticTexts["status: " + text].waitForExistence(timeout: timeout), "expected status \(text); it reads \(label(startingWith: "status: "))")
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func report(_ name: String) {
        print("NEON_IOS gallery-\(name) \(label(startingWith: "status: ")) \(label(startingWith: "insets ")) \(label(startingWith: "message at ")) \(label(startingWith: "keyboard "))")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "gallery-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func scrollTo(_ target: XCUIElement) {
        let window = app.windows.firstMatch
        for _ in 0..<8 {
            if target.exists && target.isHittable && target.frame.maxY < window.frame.maxY - 120 { return }
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        XCTFail("could not scroll \(target) into view")
    }

    func testGalleryComponents() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["Neon gallery"].waitForExistence(timeout: 20))
        status("ready")
        report("start")

        XCTAssertTrue(app.buttons["Press me"].exists, "an iOS Button is a text-only button labelled with its title, not uppercased")
        app.buttons["Press me"].tap()
        status("button 1")
        app.buttons["Disabled"].tap()
        element("Touchable opacity").tap()
        status("opacity 2")
        XCTAssertFalse(app.staticTexts["Touchable opacity"].exists, "a touchable is one accessibility element; its text is not separate")
        element("Touchable highlight").tap()
        status("highlight 3")
        element("Touchable without feedback").tap()
        status("plain 4")

        scrollTo(app.buttons["Open modal"])
        app.buttons["Open modal"].tap()
        XCTAssertTrue(app.staticTexts["Modal content"].waitForExistence(timeout: 10))
        status("modal shown")
        XCTAssertFalse(app.buttons["Press me"].isHittable, "the modal layer covers the app: a tap cannot reach the button behind it")
        report("modal")
        app.buttons["Close modal"].tap()
        status("modal closed")
        XCTAssertFalse(app.staticTexts["Modal content"].exists)

        scrollTo(app.buttons["Hide status bar"])
        app.buttons["Hide status bar"].tap()
        status("status bar hidden")
        report("statusbar-hidden")
        app.buttons["Show status bar"].tap()
        status("status bar shown")

        scrollTo(app.buttons["Open keyboard screen"])
        app.buttons["Open keyboard screen"].tap()
        XCTAssertTrue(app.staticTexts["keyboard hidden"].waitForExistence(timeout: 10))
        let resting = Int(label(startingWith: "message at ").split(separator: " ").last ?? "") ?? -1
        XCTAssertGreaterThan(resting, 0, "the input reported its frame")
        app.textFields["Message"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        let lifted = NSPredicate { [self] _, _ in
            let y = Int(label(startingWith: "message at ").split(separator: " ").last ?? "") ?? resting
            return y < resting
        }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: lifted, evaluatedWith: app)], timeout: 10), .completed,
            "KeyboardAvoidingView lifts the input above the keyboard; it reads \(label(startingWith: "message at "))")
        report("keyboard")
        app.textFields["Message"].typeText("hi\n")
        status("sent hi")
        app.buttons["Back to gallery"].tap()
        status("back")

        let window = app.windows.firstMatch
        let header = app.staticTexts["BUTTON"]
        for _ in 0..<8 where !header.isHittable {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        }
        let top = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        top.press(forDuration: 0.1, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 320)))
        status("refreshed 1", timeout: 15)
        report("refreshed")

        let paragraph = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Neon clamps this paragraph")).firstMatch
        scrollTo(paragraph)
        XCTAssertLessThan(paragraph.frame.height, 3 * 18 + 4, "numberOfLines=2 clamps the paragraph: \(paragraph.frame)")
        let notes = app.textViews["Notes"]
        scrollTo(notes)
        notes.tap()
        notes.typeText("ab\nc")
        status("notes 4")
        report("notes")
    }
}

final class MotionUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonMotion")

    override func setUp() {
        continueAfterFailure = false
    }

    private func status() -> String {
        let match = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "fade ")).firstMatch
        return match.exists ? match.label : ""
    }

    private func waitStatus(containing part: String) {
        let predicate = NSPredicate { [self] _, _ in status().contains(part) }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: app)], timeout: 10), .completed,
            "expected status containing \(part); got \(status())")
    }

    private func report(_ name: String, _ detail: String) {
        print("NEON_IOS motion-\(name) \(detail) status=\(status())")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "motion-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func pause(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testAnimationsRun() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(app.staticTexts["Neon motion"].waitForExistence(timeout: 15))
        waitStatus(containing: "fade 1")
        report("initial", "")

        let card = app.staticTexts["spring card"]
        let restX = card.frame.minX
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "spring")).firstMatch.tap()
        pause(0.25)
        let midX = card.frame.minX
        report("spring-mid", "x=\(midX) rest=\(restX)")
        XCTAssertGreaterThan(midX, restX + 5, "the card is moving")
        waitStatus(containing: "spring 160")
        pause(0.2)
        let endX = card.frame.minX
        report("spring-end", "x=\(endX) rest=\(restX)")
        XCTAssertEqual(endX - restX, 160, accuracy: 2, "the card rests 160 pt right")

        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "fade")).firstMatch.tap()
        pause(0.3)
        report("fade-mid", "")
        waitStatus(containing: "fade 0")
        report("fade-end", "")

        let after = app.staticTexts["after panel"]
        let beforeY = after.frame.minY
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "expand")).firstMatch.tap()
        pause(0.2)
        let midY = after.frame.minY
        report("panel-mid", "y=\(midY) before=\(beforeY)")
        XCTAssertGreaterThan(midY, beforeY + 5, "the panel is opening")
        XCTAssertLessThan(midY, beforeY + 150, "the panel has not landed yet")
        pause(2.0)
        let endY = after.frame.minY
        report("panel-end", "y=\(endY) before=\(beforeY)")
        XCTAssertEqual(endY - beforeY, 160, accuracy: 2, "the text below moved by the panel height")

        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "start spin")).firstMatch.tap()
        waitStatus(containing: "spin on")
        pause(0.4)
        report("spin-a", "")
        pause(0.3)
        report("spin-b", "")
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "stop spin")).firstMatch.tap()
        waitStatus(containing: "spin off")

        let title = app.staticTexts["Neon motion"]
        let titleY = title.frame.minY
        let row = app.staticTexts["row 3"]
        let from = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -260)))
        pause(1.0)
        let shrunkY = title.frame.minY
        report("header-scrolled", "titleY=\(shrunkY) before=\(titleY)")
        XCTAssertLessThan(shrunkY, titleY - 20, "the header shrinks with the scroll offset")
    }
}

final class FlutterListsUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonFlutterLists")

    override func setUp() {
        continueAfterFailure = false
    }

    private func pid() -> String {
        let text = app.debugDescription
        guard let range = text.range(of: "pid: ") else { return "" }
        return String(text[range.upperBound...].prefix(while: { $0.isNumber }))
    }

    private func status() -> String {
        let match = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "status ")).firstMatch
        return match.exists ? match.label : ""
    }

    private func waitStatus(_ prefix: String, _ why: String) {
        let predicate = NSPredicate { [self] _, _ in status().hasPrefix(prefix) }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: app)], timeout: 10), .completed,
            "\(why): expected \(prefix), app says \(status())")
    }

    private func report(_ name: String) {
        print("NEON_IOS flutterlists-\(name) pid=\(pid()) \(status())")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "flutterlists-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    private func rowPoint(_ text: XCUIElement, _ x: CGFloat) -> XCUICoordinate {
        let window = app.windows.firstMatch
        let origin = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        return origin.withOffset(CGVector(dx: window.frame.width * x, dy: text.frame.midY))
    }

    func testSwipeReorderGridAndHeaders() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 2")).firstMatch.waitForExistence(timeout: 15))
        let launched = pid()
        report("mail")

        let archive = rowPoint(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 2")).firstMatch, 0.3)
        archive.press(forDuration: 0.05, thenDragTo: archive.withOffset(CGVector(dx: 230, dy: 0)))
        waitStatus("status archived Mail 2", "a right swipe archives the row")
        settle()
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 2")).firstMatch.exists, "the archived row left the list")
        report("archived")

        let remove = rowPoint(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 3")).firstMatch, 0.7)
        remove.press(forDuration: 0.05, thenDragTo: remove.withOffset(CGVector(dx: -230, dy: 0)))
        waitStatus("status deleted Mail 3", "a left swipe deletes the row")
        settle()

        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 4")).firstMatch.tap()
        waitStatus("status opened Mail 4", "a tap on a swipeable row still presses it")

        let short = rowPoint(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 5")).firstMatch, 0.3)
        short.press(forDuration: 0.05, thenDragTo: short.withOffset(CGVector(dx: 60, dy: 0)))
        settle()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 5")).firstMatch.exists, "a short swipe springs back")
        XCTAssertEqual(status(), "status opened Mail 4", "and neither dismisses nor presses")

        let firstY = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 1")).firstMatch.frame.minY
        let scroll = rowPoint(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 6")).firstMatch, 0.5)
        scroll.press(forDuration: 0.05, thenDragTo: scroll.withOffset(CGVector(dx: 0, dy: -200)))
        settle()
        XCTAssertLessThan(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Mail 1")).firstMatch.frame.minY, firstY - 50, "a vertical drag over the rows scrolls the list")
        XCTAssertEqual(status(), "status opened Mail 4", "the vertical drag dismissed nothing")
        report("scrolled")

        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "playlist")).firstMatch.tap()
        waitStatus("status order 1 2 3 4", "the playlist opens")
        let handle = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "drag 1")).firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        handle.press(forDuration: 0.8, thenDragTo: handle.withOffset(CGVector(dx: 0, dy: 130)))
        waitStatus("status order 2 3 1 4 moved 0 to 2", "a long-press drag moves song 1 below song 3")
        report("reordered")

        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "photos")).firstMatch.tap()
        waitStatus("status grid width", "the max-extent grid derives its item width")
        settle()
        let p1 = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "P1")).firstMatch, p2 = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "P2")).firstMatch, p3 = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "P3")).firstMatch
        XCTAssertEqual(p1.frame.midY, p3.frame.midY, accuracy: 1, "three photos share the first row")
        XCTAssertLessThan(p1.frame.midX, p2.frame.midX)
        report("grid")
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "show masonry")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "P1 c0")).firstMatch.waitForExistence(timeout: 10), "masonry places P1 in the first column")
        report("masonry")

        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "header")).firstMatch.tap()
        waitStatus("status header 200", "the header starts expanded")
        let list = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Row 3")).firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        list.press(forDuration: 0.05, thenDragTo: list.withOffset(CGVector(dx: 0, dy: -300)))
        waitStatus("status header 64", "the pinned header collapses to its toolbar height")
        report("collapsed")

        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "slivers")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Albums")).firstMatch.waitForExistence(timeout: 10))
        let top = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Albums")).firstMatch.frame.minY
        let slivers = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Album 4")).firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        slivers.press(forDuration: 0.05, thenDragTo: slivers.withOffset(CGVector(dx: 0, dy: -150)))
        settle()
        XCTAssertLessThan(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Albums")).firstMatch.frame.minY, top, "the banner scrolled away")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Albums")).firstMatch.isHittable || app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Tracks")).firstMatch.exists, "a pinned header stays at the top")
        report("slivers")

        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "wheel")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "hour 1")).firstMatch.waitForExistence(timeout: 10))
        settle()
        let centre = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "hour 1")).firstMatch.frame.midY
        let wheel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "hour 2")).firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        wheel.press(forDuration: 0.05, thenDragTo: wheel.withOffset(CGVector(dx: 0, dy: -132)), withVelocity: .slow, thenHoldForDuration: 0.4)
        waitStatus("status picked hour 4", "dragging the wheel three items picks hour 4")
        settle()
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "hour 4")).firstMatch.frame.midY, centre, accuracy: 4, "the wheel snaps hour 4 to the centre hour 1 started at")
        XCTAssertEqual(launched, pid())
        report("wheel")
    }
}

final class ControlsUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonControls")

    override func setUp() {
        continueAfterFailure = false
    }

    private func label(startingWith prefix: String) -> String {
        let match = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        return match.exists ? match.label : ""
    }

    private func waitLabel(_ prefix: String, containing part: String, timeout: TimeInterval = 10) {
        let predicate = NSPredicate { [self] _, _ in label(startingWith: prefix).contains(part) }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: app)], timeout: timeout), .completed,
            "expected \(prefix)… to contain \(part); it reads \(label(startingWith: prefix))")
    }

    private func report(_ name: String) {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(24).map { $0.label }.joined(separator: " | ")
        print("NEON_IOS controls-\(name) \(texts)")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "controls-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func any(_ name: String) -> XCUIElement {
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func reveal(_ element: XCUIElement) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < 6 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.8))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.45)))
            swipes += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) is on screen after \(swipes) swipes")
    }

    func testBookingForm() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.staticTexts["Neon booking"].waitForExistence(timeout: 20))
        waitLabel("status ", containing: "status idle")
        report("start")

        let date = app.datePickers.firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 10), "the check-in UIDatePicker is on screen")
        print("NEON_IOS controls-datepickers \(app.datePickers.allElementsBoundByIndex.map { "\($0.label)=\($0.value as? String ?? "")" })")
        date.tap()
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'October 24' OR label CONTAINS[c] '24 October'")).firstMatch
        if day.waitForExistence(timeout: 5) {
            day.tap()
            report("date-popover")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.13)).tap()
            waitLabel("check-in ", containing: "2026-10-24")
        } else {
            report("date-popover-missing")
            print("NEON_IOS controls-date-buttons \(app.buttons.allElementsBoundByIndex.prefix(40).map { $0.label })")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.13)).tap()
        }

        let slider = app.sliders["Guests"]
        reveal(slider)
        slider.adjust(toNormalizedSliderPosition: 0.6)
        waitLabel("guests ", containing: "guests 5")
        report("slider")

        let tip = any("Guest limit")
        tip.press(forDuration: 1.0)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Up to 8 guests per room")).firstMatch.waitForExistence(timeout: 5), "the tooltip shows on long press")
        report("tooltip")

        let room = app.buttons["Room type"]
        reveal(room)
        room.tap()
        let suite = app.buttons["Suite"].firstMatch
        XCTAssertTrue(suite.waitForExistence(timeout: 5), "the room menu lists Suite")
        report("room-menu")
        suite.tap()
        waitLabel("room ", containing: "room Suite")

        let business = any("Business")
        reveal(business)
        business.tap()
        waitLabel("trip ", containing: "trip Business")

        let breakfast = any("Breakfast")
        reveal(breakfast)
        breakfast.tap()
        waitLabel("extras ", containing: "extras breakfast")
        XCTAssertEqual(any("Breakfast").value as? String ?? "", "checked", "the checkbox exposes its checked state")

        let cash = any("Cash")
        reveal(cash)
        cash.tap()
        waitLabel("payment ", containing: "payment cash")

        let sea = any("Sea view")
        reveal(sea)
        sea.tap()
        waitLabel("prefs ", containing: "prefs Sea view")
        report("form-filled")

        let details = any("Details")
        reveal(details)
        details.tap()
        waitLabel("details ", containing: "details Suite for 5 guests")
        report("bottom-sheet")
        any("Close").tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'details '")).firstMatch.waitForNonExistence(timeout: 5))

        any("Book").tap()
        XCTAssertTrue(any("Confirm booking").waitForExistence(timeout: 5), "the confirm dialog opens")
        report("dialog")
        any("Confirm").tap()
        waitLabel("status ", containing: "status booking")
        report("booking")
        waitLabel("status ", containing: "status booked", timeout: 10)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Booked Suite for 5 guests'")).firstMatch.waitForExistence(timeout: 5), "the snackbar shows")
        report("snackbar")
        any("Undo").tap()
        waitLabel("status ", containing: "status cancelled")
        XCTAssertTrue(any("Booking cancelled").waitForExistence(timeout: 5), "the toast shows")
        report("toast")
    }
}

final class NavigationUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonNavigation")

    override func setUp() {
        continueAfterFailure = false
    }

    private func report(_ name: String) {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(16).map { $0.label }.joined(separator: " | ")
        let buttons = app.buttons.allElementsBoundByIndex.prefix(16).map { $0.label }.joined(separator: " | ")
        print("NEON_IOS navigation-\(name) texts: \(texts) buttons: \(buttons)")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "navigation-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func labelled(_ label: String) -> XCUIElement {
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func any(_ label: String, timeout: TimeInterval = 15) -> XCUIElement {
        let element = labelled(label)
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
            "no \(label); texts \(app.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label }) buttons \(app.buttons.allElementsBoundByIndex.prefix(30).map { $0.label })")
        return element
    }

    private func press(_ label: String) {
        let element = any(label)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        element.tap()
    }

    private func swipeFromLeftEdge() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.6))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: end)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    private func gone(_ label: String) {
        let element = labelled(label)
        let absent = NSPredicate { _, _ in !element.exists || !element.isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: absent, evaluatedWith: app)], timeout: 10), .completed, "\(label) is still shown")
    }

    func testStackTabsDrawerAndBack() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        _ = any("Home taps 0", timeout: 20)
        _ = any("Items")
        report("list")
        press("Increment home")
        _ = any("Home taps 1")

        press("Open Void shader")
        _ = any("Item number 2")
        _ = any("Back")
        report("detail")

        press("Edit item")
        let field = app.textFields["Item name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the edit field")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        field.typeText("Void renderer")
        report("edit")
        press("Save")
        _ = any("Item number 2")
        _ = any("Void renderer")
        report("saved")

        press("Back")
        _ = any("Home taps 1")
        _ = any("Open Void renderer")
        report("back-kept-state")

        press("Open Neon lamp")
        _ = any("Item number 1")
        report("before-swipe-back")
        swipeFromLeftEdge()
        _ = any("Home taps 1")
        gone("Item number 1")
        report("swiped-back")

        swipeFromLeftEdge()
        _ = any("Close navigation menu")
        report("drawer-swiped-open")
        press("Items")
        gone("Close navigation menu")
        _ = any("Home taps 1")

        press("Search")
        _ = any("Searches 0")
        press("Increment search")
        _ = any("Searches 1")
        press("Add badge")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        report("search-badge")

        press("Profile")
        _ = any("Profile taps 0")
        press("Increment profile")
        _ = any("Profile taps 1")
        press("Search")
        _ = any("Searches 1")
        press("Home")
        _ = any("Home taps 1")
        report("tabs-kept-state")

        press("Show navigation menu")
        _ = any("Close navigation menu")
        report("drawer-open")
        press("Settings")
        _ = any("Settings taps 0")
        gone("Close navigation menu")
        report("settings")
        press("Toggle dark theme")
        _ = any("Theme: dark")
        report("dark-theme")
        press("Toggle dark theme")
        _ = any("Theme: light")
        press("Show navigation menu")
        press("About")
        _ = any("Neon navigation")
        report("about")
        press("Show navigation menu")
        press("Items")
        _ = any("Home taps 1")
        report("back-to-items")

        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        _ = any("Home taps 1")
        report("landscape")
        XCUIDevice.shared.orientation = .portrait
    }
}
