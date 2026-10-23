import Foundation

/// Something a window shortcut does to the focused window.
public enum WindowAction: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, center, restore
    case nextDisplay, previousDisplay

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .maximize: "Maximize"
        case .center: "Center"
        case .restore: "Restore"
        case .nextDisplay: "Next Display"
        case .previousDisplay: "Previous Display"
        }
    }

    /// The part of the screen this action fills. Nil for actions that keep
    /// the window's size.
    public var region: ScreenRegion? {
        switch self {
        case .leftHalf: ScreenRegion(left: 0, top: 0, right: 1 / 2, bottom: 1)
        case .rightHalf: ScreenRegion(left: 1 / 2, top: 0, right: 1, bottom: 1)
        case .topHalf: ScreenRegion(left: 0, top: 0, right: 1, bottom: 1 / 2)
        case .bottomHalf: ScreenRegion(left: 0, top: 1 / 2, right: 1, bottom: 1)
        case .topLeft: ScreenRegion(left: 0, top: 0, right: 1 / 2, bottom: 1 / 2)
        case .topRight: ScreenRegion(left: 1 / 2, top: 0, right: 1, bottom: 1 / 2)
        case .bottomLeft: ScreenRegion(left: 0, top: 1 / 2, right: 1 / 2, bottom: 1)
        case .bottomRight: ScreenRegion(left: 1 / 2, top: 1 / 2, right: 1, bottom: 1)
        case .leftThird: ScreenRegion(left: 0, top: 0, right: 1 / 3, bottom: 1)
        case .centerThird: ScreenRegion(left: 1 / 3, top: 0, right: 2 / 3, bottom: 1)
        case .rightThird: ScreenRegion(left: 2 / 3, top: 0, right: 1, bottom: 1)
        case .leftTwoThirds: ScreenRegion(left: 0, top: 0, right: 2 / 3, bottom: 1)
        case .rightTwoThirds: ScreenRegion(left: 1 / 3, top: 0, right: 1, bottom: 1)
        case .maximize: ScreenRegion(left: 0, top: 0, right: 1, bottom: 1)
        case .center, .restore, .nextDisplay, .previousDisplay: nil
        }
    }
}

/// A rectangle in fractions of a screen's visible area, measured from its
/// top-left corner.
public struct ScreenRegion: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

/// One screen. Both frames use Accessibility coordinates: the origin is the
/// top-left corner of the main screen and y grows downward.
public struct Display: Equatable, Sendable {
    /// The whole screen.
    public var frame: CGRect
    /// The screen minus the menu bar and the Dock.
    public var visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// Window geometry for the window shortcuts. Pure math, no Accessibility
/// calls, so it can be tested anywhere.
public enum WindowLayout {
    /// The frame `action` gives a window that is at `window` now. Nil when
    /// there is nothing to do: `restore` (the caller remembers frames), a
    /// display move with one screen, or no screens.
    public static func frame(for action: WindowAction, window: CGRect, displays: [Display]) -> CGRect? {
        guard let index = displayIndex(for: window, among: displays) else { return nil }
        let visible = displays[index].visibleFrame
        if let region = action.region {
            return frame(of: region, in: visible)
        }
        switch action {
        case .center:
            return centered(window.size, in: visible)
        case .nextDisplay, .previousDisplay:
            guard let next = neighbor(of: index, among: displays, forward: action == .nextDisplay) else {
                return nil
            }
            return moved(window, from: visible, to: displays[next].visibleFrame)
        default:
            return nil
        }
    }

    /// Edges at 0 and 1 stay exactly on the screen edge. Edges inside the
    /// screen are rounded to whole points, so neighbors (left and right half,
    /// the three thirds) meet without a gap or overlap.
    public static func frame(of region: ScreenRegion, in visible: CGRect) -> CGRect {
        func edge(_ start: CGFloat, _ length: CGFloat, _ fraction: Double) -> CGFloat {
            switch fraction {
            case 0: start
            case 1: start + length
            default: (start + length * CGFloat(fraction)).rounded()
            }
        }
        let minX = edge(visible.minX, visible.width, region.left)
        let maxX = edge(visible.minX, visible.width, region.right)
        let minY = edge(visible.minY, visible.height, region.top)
        let maxY = edge(visible.minY, visible.height, region.bottom)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The fixed layout `window` is in, if any (within `tolerance` points).
    public static func matchingAction(for window: CGRect, in visible: CGRect, tolerance: CGFloat = 2) -> WindowAction? {
        WindowAction.allCases.first { action in
            guard let region = action.region else { return false }
            return isClose(frame(of: region, in: visible), window, tolerance: tolerance)
        }
    }

    /// `size` (no bigger than `visible`) centered in `visible`.
    public static func centered(_ size: CGSize, in visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        return CGRect(
            x: (visible.midX - width / 2).rounded(),
            y: (visible.midY - height / 2).rounded(),
            width: width,
            height: height
        )
    }

    /// `window` on another screen. A window in a fixed layout (left half, top
    /// right quarter…) gets the same layout there. Any other window keeps its
    /// size and the relative position of its center.
    public static func moved(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        if let action = matchingAction(for: window, in: source), let region = action.region {
            return frame(of: region, in: target)
        }
        guard source.width > 0, source.height > 0 else { return centered(window.size, in: target) }
        let width = min(window.width, target.width)
        let height = min(window.height, target.height)
        let centerX = target.minX + (window.midX - source.minX) / source.width * target.width
        let centerY = target.minY + (window.midY - source.minY) / source.height * target.height
        let rect = CGRect(
            x: (centerX - width / 2).rounded(),
            y: (centerY - height / 2).rounded(),
            width: width,
            height: height
        )
        return keptInside(rect, bounds: target)
    }

    /// `rect` shifted, never resized, so it lies inside `bounds`. When it is
    /// bigger than `bounds`, its top-left corner goes to the top-left corner.
    /// Used after a window refuses a size (it has a minimum or fixed size).
    public static func keptInside(_ rect: CGRect, bounds: CGRect) -> CGRect {
        var result = rect
        result.origin.x = max(min(rect.minX, bounds.maxX - rect.width), bounds.minX)
        result.origin.y = max(min(rect.minY, bounds.maxY - rect.height), bounds.minY)
        return result
    }

    /// The screen holding most of `window`, or the nearest one when none
    /// overlaps it. Nil only when there are no screens.
    public static func displayIndex(for window: CGRect, among displays: [Display]) -> Int? {
        guard !displays.isEmpty else { return nil }
        let overlaps = displays.map { overlapArea(window, $0.frame) }
        if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
            return best
        }
        func distance(_ display: Display) -> CGFloat {
            let dx = display.frame.midX - window.midX
            let dy = display.frame.midY - window.midY
            return dx * dx + dy * dy
        }
        return displays.indices.min { distance(displays[$0]) < distance(displays[$1]) }
    }

    /// The screen after (or before) `index`, left to right then top to
    /// bottom, wrapping around. Nil with fewer than two screens.
    public static func neighbor(of index: Int, among displays: [Display], forward: Bool) -> Int? {
        guard displays.count > 1, displays.indices.contains(index) else { return nil }
        let order = displays.indices.sorted {
            let a = displays[$0].frame, b = displays[$1].frame
            return a.minX != b.minX ? a.minX < b.minX : a.minY < b.minY
        }
        guard let position = order.firstIndex(of: index) else { return nil }
        let step = forward ? 1 : order.count - 1
        return order[(position + step) % order.count]
    }

    /// Converts between AppKit coordinates (origin at the bottom-left of the
    /// main screen, y up) and Accessibility coordinates (origin at its
    /// top-left, y down). Applying it twice gives back `rect`.
    public static func flipped(_ rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let width = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let height = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return width > 0 && height > 0 ? width * height : 0
    }
}

/// Where each window was before PEA first moved it, so Restore can put it
/// back. Moving it again keeps the first frame, unless the window was
/// moved by hand in between.
public struct RestoreFrames<Key: Hashable> {
    private struct Entry {
        var original: CGRect
        var placed: CGRect
    }

    public let capacity: Int
    private var entries: [Key: Entry] = [:]
    /// Oldest first, for dropping entries past `capacity`.
    private var order: [Key] = []

    public init(capacity: Int = 100) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { entries.count }

    /// Records a move of `key` from `current` to `placed`.
    public mutating func record(_ key: Key, from current: CGRect, to placed: CGRect) {
        if let entry = entries[key], WindowLayout.isClose(entry.placed, current) {
            entries[key]?.placed = placed
            return
        }
        if entries[key] == nil {
            order.append(key)
        }
        entries[key] = Entry(original: current, placed: placed)
        while order.count > capacity {
            entries[order.removeFirst()] = nil
        }
    }

    /// The frame to restore `key` to, and forgets it.
    public mutating func takeOriginal(_ key: Key) -> CGRect? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        order.removeAll { $0 == key }
        return entry.original
    }
}
