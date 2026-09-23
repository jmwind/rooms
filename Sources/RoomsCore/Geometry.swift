import CoreGraphics

/// A rectangle as fractions of a screen's usable area, so layouts survive
/// resolution changes and different displays.
public struct FractionalFrame: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// All rectangles here use the Accessibility coordinate space: origin at the top-left
/// of the primary display, y growing downwards.
public enum Geometry {
    public static func fraction(of rect: CGRect, in container: CGRect) -> FractionalFrame {
        guard container.width > 0, container.height > 0 else { return FractionalFrame(x: 0, y: 0, w: 1, h: 1) }
        return FractionalFrame(
            x: round4((rect.minX - container.minX) / container.width),
            y: round4((rect.minY - container.minY) / container.height),
            w: round4(rect.width / container.width),
            h: round4(rect.height / container.height)
        )
    }

    public static func resolve(_ f: FractionalFrame, in container: CGRect) -> CGRect {
        CGRect(
            x: (container.minX + f.x * container.width).rounded(),
            y: (container.minY + f.y * container.height).rounded(),
            width: (f.w * container.width).rounded(),
            height: (f.h * container.height).rounded()
        )
    }

    /// Converts a Cocoa rectangle (origin bottom-left of the primary display) to AX space.
    public static func axRect(fromCocoa r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Where to park a window so only a 1 pt sliver stays on `screen` (AeroSpace's
    /// technique). Tries each corner and takes the first where the whole parked window
    /// stays clear of every other display (a monitor above, beside or below); if none
    /// is clear, the corner where the least of it lands on another display.
    public static func parkingOrigin(windowSize w: CGSize, screen s: CGRect, otherScreens: [CGRect]) -> CGPoint {
        let corners = [
            CGPoint(x: s.maxX - 1, y: s.maxY - 1),                    // bottom right
            CGPoint(x: s.minX + 1 - w.width, y: s.maxY - 1),          // bottom left
            CGPoint(x: s.maxX - 1, y: s.minY + 1 - w.height),         // top right
            CGPoint(x: s.minX + 1 - w.width, y: s.minY + 1 - w.height), // top left
        ]
        func spill(_ origin: CGPoint) -> CGFloat {
            let parked = CGRect(origin: origin, size: w)
            return otherScreens.reduce(0) { sum, other in
                let overlap = other.intersection(parked)
                return sum + (overlap.isNull ? 0 : overlap.width * overlap.height)
            }
        }
        return corners.first { spill($0) == 0 } ?? corners.min { spill($0) < spill($1) }!
    }

    /// A window's way back, kept on a connected display: if `rect` is on none of
    /// `screens` (the display it was parked from is gone), it moves to the first one,
    /// shrunk to fit if needed.
    public static func keptOnScreen(_ rect: CGRect, screens: [CGRect]) -> CGRect {
        guard let first = screens.first, bestScreen(for: rect, among: screens) == nil else { return rect }
        let size = CGSize(width: min(rect.width, first.width), height: min(rect.height, first.height))
        return CGRect(origin: CGPoint(x: first.midX - size.width / 2, y: first.midY - size.height / 2), size: size)
    }

    /// The screen that holds most of `rect`, or nil when it's on none of them.
    public static func bestScreen(for rect: CGRect, among screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (i, s) in screens.enumerated() {
            let overlap = s.intersection(rect)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (i, area) }
        }
        return best?.index
    }

    private static func round4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
}
