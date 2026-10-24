import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import PEACore

final class WindowLayoutTests: XCTestCase {
    // A 1440×900 main screen with a 25 pt menu bar, and a 1920×1080 screen
    // to its left, slightly lower. Accessibility coordinates (y down).
    private let main = Display(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875)
    )
    private let left = Display(
        frame: CGRect(x: -1920, y: 100, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 125, width: 1920, height: 1055)
    )
    private let window = CGRect(x: 200, y: 200, width: 800, height: 500)

    func testHalvesAndQuarters() {
        let displays = [main]
        XCTAssertEqual(WindowLayout.frame(for: .leftHalf, window: window, displays: displays),
                       CGRect(x: 0, y: 25, width: 720, height: 875))
        XCTAssertEqual(WindowLayout.frame(for: .rightHalf, window: window, displays: displays),
                       CGRect(x: 720, y: 25, width: 720, height: 875))
        XCTAssertEqual(WindowLayout.frame(for: .topHalf, window: window, displays: displays),
                       CGRect(x: 0, y: 25, width: 1440, height: 438))
        XCTAssertEqual(WindowLayout.frame(for: .bottomHalf, window: window, displays: displays),
                       CGRect(x: 0, y: 463, width: 1440, height: 437))
        XCTAssertEqual(WindowLayout.frame(for: .bottomRight, window: window, displays: displays),
                       CGRect(x: 720, y: 463, width: 720, height: 437))
        XCTAssertEqual(WindowLayout.frame(for: .maximize, window: window, displays: displays),
                       main.visibleFrame)
    }

    func testThirdsTileWithoutGaps() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let thirds = [WindowAction.leftThird, .centerThird, .rightThird].map {
            WindowLayout.frame(of: $0.region!, in: visible)
        }
        XCTAssertEqual(thirds[0].minX, 0)
        XCTAssertEqual(thirds[0].maxX, thirds[1].minX)
        XCTAssertEqual(thirds[1].maxX, thirds[2].minX)
        XCTAssertEqual(thirds[2].maxX, 1000)
        XCTAssertEqual(thirds.map(\.width).reduce(0, +), 1000)
        XCTAssertTrue(thirds.allSatisfy { $0.minX == $0.minX.rounded() && $0.width == $0.width.rounded() })

        let twoThirds = WindowLayout.frame(of: WindowAction.leftTwoThirds.region!, in: visible)
        XCTAssertEqual(twoThirds.maxX, thirds[1].maxX)
    }

    func testOddWidthHalvesMeet() {
        let visible = CGRect(x: 0, y: 25, width: 1441, height: 875)
        let leftHalf = WindowLayout.frame(of: WindowAction.leftHalf.region!, in: visible)
        let rightHalf = WindowLayout.frame(of: WindowAction.rightHalf.region!, in: visible)
        XCTAssertEqual(leftHalf.maxX, rightHalf.minX)
        XCTAssertEqual(rightHalf.maxX, 1441)
    }

    func testUsesTheScreenTheWindowIsOn() {
        let onLeft = CGRect(x: -1500, y: 300, width: 600, height: 400)
        XCTAssertEqual(WindowLayout.frame(for: .leftHalf, window: onLeft, displays: [main, left]),
                       CGRect(x: -1920, y: 125, width: 960, height: 1055))
    }

    func testCenterKeepsSizeAndCapsIt() {
        XCTAssertEqual(WindowLayout.frame(for: .center, window: window, displays: [main]),
                       CGRect(x: 320, y: 213, width: 800, height: 500))
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        XCTAssertEqual(WindowLayout.frame(for: .center, window: huge, displays: [main]), main.visibleFrame)
    }

    func testRestoreIsLeftToTheCaller() {
        XCTAssertNil(WindowLayout.frame(for: .restore, window: window, displays: [main]))
        XCTAssertNil(WindowLayout.frame(for: .leftHalf, window: window, displays: []))
    }

    func testDisplayIndexPicksLargestOverlapThenNearest() {
        let straddling = CGRect(x: -300, y: 200, width: 1000, height: 400) // mostly on main
        XCTAssertEqual(WindowLayout.displayIndex(for: straddling, among: [left, main]), 1)
        let lost = CGRect(x: -2600, y: 300, width: 200, height: 200) // off every screen, left of `left`
        XCTAssertEqual(WindowLayout.displayIndex(for: lost, among: [main, left]), 1)
        XCTAssertNil(WindowLayout.displayIndex(for: window, among: []))
    }

    func testNeighborGoesLeftToRightAndWraps() {
        let right = Display(
            frame: CGRect(x: 1440, y: 0, width: 1280, height: 800),
            visibleFrame: CGRect(x: 1440, y: 0, width: 1280, height: 800)
        )
        let displays = [main, right, left] // NSScreen order is not spatial
        XCTAssertEqual(WindowLayout.neighbor(of: 2, among: displays, forward: true), 0)
        XCTAssertEqual(WindowLayout.neighbor(of: 0, among: displays, forward: true), 1)
        XCTAssertEqual(WindowLayout.neighbor(of: 1, among: displays, forward: true), 2)
        XCTAssertEqual(WindowLayout.neighbor(of: 2, among: displays, forward: false), 1)
        XCTAssertNil(WindowLayout.neighbor(of: 0, among: [main], forward: true))
    }

    func testMovingKeepsLayoutOrSize() {
        let displays = [main, left]
        let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
        XCTAssertEqual(WindowLayout.frame(for: .nextDisplay, window: leftHalf, displays: displays),
                       CGRect(x: -1920, y: 125, width: 960, height: 1055))

        // A free window keeps its size; its center keeps its relative place.
        let moved = WindowLayout.frame(for: .previousDisplay, window: window, displays: displays)
        XCTAssertEqual(moved?.size, window.size)
        XCTAssertTrue(left.visibleFrame.contains(moved!))
        XCTAssertNil(WindowLayout.frame(for: .nextDisplay, window: window, displays: [main]))
    }

    func testMovingABigWindowToASmallScreenShrinksIt() {
        let small = CGRect(x: 1440, y: 0, width: 1024, height: 700)
        let big = CGRect(x: 100, y: 100, width: 1200, height: 760)
        let moved = WindowLayout.moved(big, from: main.visibleFrame, to: small)
        XCTAssertEqual(moved.size, CGSize(width: 1024, height: 700))
        XCTAssertEqual(moved.origin, small.origin)
    }

    func testKeptInsideShiftsButNeverResizes() {
        let bounds = CGRect(x: 0, y: 25, width: 1440, height: 875)
        // Asked for the right half, but the window is at least 900 wide.
        let wide = CGRect(x: 720, y: 25, width: 900, height: 875)
        XCTAssertEqual(WindowLayout.keptInside(wide, bounds: bounds), CGRect(x: 540, y: 25, width: 900, height: 875))
        let fine = CGRect(x: 10, y: 30, width: 100, height: 100)
        XCTAssertEqual(WindowLayout.keptInside(fine, bounds: bounds), fine)
        let tooBig = CGRect(x: 300, y: 300, width: 2000, height: 1000)
        XCTAssertEqual(WindowLayout.keptInside(tooBig, bounds: bounds).origin, bounds.origin)
    }

    func testFlipRoundTrips() {
        let appKit = CGRect(x: 10, y: 0, width: 100, height: 100)
        let flipped = WindowLayout.flipped(appKit, mainScreenHeight: 900)
        XCTAssertEqual(flipped, CGRect(x: 10, y: 800, width: 100, height: 100))
        XCTAssertEqual(WindowLayout.flipped(flipped, mainScreenHeight: 900), appKit)
    }

    func testMatchingAction() {
        let visible = main.visibleFrame
        XCTAssertEqual(WindowLayout.matchingAction(for: CGRect(x: 1, y: 25, width: 719, height: 875), in: visible), .leftHalf)
        XCTAssertEqual(WindowLayout.matchingAction(for: visible, in: visible), .maximize)
        XCTAssertNil(WindowLayout.matchingAction(for: window, in: visible))
    }

    func testEveryActionHasATitle() {
        XCTAssertEqual(Set(WindowAction.allCases.map(\.title)).count, WindowAction.allCases.count)
    }
}

final class RestoreFramesTests: XCTestCase {
    private let original = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
    private let rightHalf = CGRect(x: 720, y: 25, width: 720, height: 875)

    func testKeepsTheFirstFrameAcrossMoves() {
        var frames = RestoreFrames<Int>()
        frames.record(1, from: original, to: leftHalf)
        frames.record(1, from: leftHalf, to: rightHalf)
        XCTAssertEqual(frames.takeOriginal(1), original)
        XCTAssertNil(frames.takeOriginal(1))
    }

    func testAMoveByHandResetsIt() {
        var frames = RestoreFrames<Int>()
        frames.record(1, from: original, to: leftHalf)
        let dragged = CGRect(x: 300, y: 300, width: 500, height: 400)
        frames.record(1, from: dragged, to: rightHalf)
        XCTAssertEqual(frames.takeOriginal(1), dragged)
    }

    func testDropsTheOldestPastCapacity() {
        var frames = RestoreFrames<Int>(capacity: 2)
        frames.record(1, from: original, to: leftHalf)
        frames.record(2, from: original, to: leftHalf)
        frames.record(3, from: original, to: leftHalf)
        XCTAssertEqual(frames.count, 2)
        XCTAssertNil(frames.takeOriginal(1))
        XCTAssertEqual(frames.takeOriginal(3), original)
    }
}
