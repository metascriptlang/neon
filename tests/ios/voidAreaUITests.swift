import XCTest

@MainActor
final class VoidAreaUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "dev.neon.NeonVoidArea")
    private let markerPoints = 40.0

    private struct Census {
        var green = 0
        var blue = 0
        var red = 0
        var scale = 1.0
    }

    override func setUp() {
        continueAfterFailure = false
    }

    private var status: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "void ")).firstMatch
    }

    private func areaSize(_ label: String) -> CGSize? {
        let parts = label.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let size = parts[1].split(separator: "x")
        guard size.count == 2, let w = Double(size[0]), let h = Double(size[1]) else { return nil }
        return CGSize(width: w, height: h)
    }

    private func settle(landscape: Bool) -> CGSize {
        let deadline = Date().addingTimeInterval(20)
        var previous = ""
        while Date() < deadline {
            let label = status.exists ? status.label : ""
            let window = app.windows.firstMatch.frame
            if let size = areaSize(label), (window.width > window.height) == landscape,
               (size.width > size.height) == landscape || !landscape, label == previous {
                RunLoop.current.run(until: Date().addingTimeInterval(1))
                return size
            }
            previous = label
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("the area never reported a \(landscape ? "landscape" : "portrait") size; status \"\(status.exists ? status.label : "missing")\", window \(app.windows.firstMatch.frame)")
        return .zero
    }

    private func census(_ name: String) -> Census {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        var result = Census()
        result.scale = Double(shot.image.scale)
        guard let image = shot.image.cgImage else {
            XCTFail("\(name): the screenshot has no bitmap")
            return result
        }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
            if g > 200 && r < 60 && b < 60 { result.green += 1 }
            else if b > 200 && r < 60 && g < 60 { result.blue += 1 }
            else if r > 200 && g < 60 && b < 60 { result.red += 1 }
        }
        print("NEON_VOID_AREA \(name) status=\"\(status.label)\" green=\(result.green) blue=\(result.blue) red=\(result.red) scale=\(result.scale)")
        return result
    }

    private func checkDrawn(_ name: String, size: CGSize) {
        let seen = census(name)
        let marker = markerPoints * seen.scale * markerPoints * seen.scale
        let area = size.width * seen.scale * size.height * seen.scale - marker
        XCTAssertEqual(seen.red, 0, "\(name): the fallback drew instead of the area")
        XCTAssertEqual(Double(seen.green), area, accuracy: area * 0.03, "\(name): the area's colour does not cover its \(size) layout")
        XCTAssertEqual(Double(seen.blue), marker, accuracy: marker * 0.1, "\(name): the \(markerPoints)pt marker is not drawn at its size, so the drawable does not follow the layer")
    }

    private func tapArea(_ expected: String) {
        let frame = status.frame
        let window = app.windows.firstMatch.frame
        let x = window.midX
        let y = frame.maxY + (window.maxY - frame.maxY) / 2
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
        let reached = NSPredicate(format: "label CONTAINS %@", expected)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: reached, evaluatedWith: status)], timeout: 5), .completed,
                       "a tap at \(x),\(y) did not reach onPointerDown in the area: \(status.label)")
    }

    func testAreaDrawsFollowsRotationAndTakesTouch() {
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        let portrait = settle(landscape: false)
        checkDrawn("portrait", size: portrait)
        tapArea("downs 1")

        XCUIDevice.shared.orientation = .landscapeRight
        let landscape = settle(landscape: true)
        XCTAssertNotEqual(portrait, landscape, "the area kept its portrait size after rotation")
        checkDrawn("landscape", size: landscape)
        tapArea("downs 2")

        XCUIDevice.shared.orientation = .portrait
        let returned = settle(landscape: false)
        XCTAssertEqual(portrait, returned, "the area did not return to its portrait size")
        checkDrawn("portrait-returned", size: returned)
    }
}
