import CoreGraphics

/// Keyboard snapping for one window (the Rectangle / Raycast set), using the same
/// 16-pt gaps as room layouts so a snapped window lines up with a tiled room.
public enum SnapAction: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, center

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
        case .firstThird: "First Third"
        case .centerThird: "Center Third"
        case .lastThird: "Last Third"
        case .firstTwoThirds: "First Two Thirds"
        case .lastTwoThirds: "Last Two Thirds"
        case .maximize: "Maximize"
        case .center: "Center"
        }
    }

    /// Pressing Left Half or Right Half again cycles ½ → ⅔ → ⅓ (Rectangle's behavior).
    public var cycles: Bool { self == .leftHalf || self == .rightHalf }

    /// Where the window goes. `visible`: the screen's usable area (AX coordinates);
    /// `window`: its current size (only Center uses it); `step`: repeat count for cycling.
    public func rect(in visible: CGRect, window: CGSize = .zero, gap: CGFloat = Tiler.gap, step: Int = 0) -> CGRect {
        let a = visible.insetBy(dx: gap, dy: gap)
        func cols(_ start: Int, _ span: Int, of n: Int) -> (x: CGFloat, w: CGFloat) {
            let unit = (a.width - gap * CGFloat(n - 1)) / CGFloat(n)
            return (a.minX + CGFloat(start) * (unit + gap), unit * CGFloat(span) + gap * CGFloat(span - 1))
        }
        func rows(_ start: Int, _ span: Int, of n: Int) -> (y: CGFloat, h: CGFloat) {
            let unit = (a.height - gap * CGFloat(n - 1)) / CGFloat(n)
            return (a.minY + CGFloat(start) * (unit + gap), unit * CGFloat(span) + gap * CGFloat(span - 1))
        }
        // Round the edges, not the sizes, so every gap stays exactly `gap` wide.
        func r(_ c: (x: CGFloat, w: CGFloat), _ w: (y: CGFloat, h: CGFloat)) -> CGRect {
            let x0 = c.x.rounded(), y0 = w.y.rounded()
            return CGRect(x: x0, y: y0, width: (c.x + c.w).rounded() - x0, height: (w.y + w.h).rounded() - y0)
        }
        let full = rows(0, 1, of: 1)
        let cycle = step % 3
        switch self {
        case .leftHalf:
            return r([cols(0, 1, of: 2), cols(0, 2, of: 3), cols(0, 1, of: 3)][cycle], full)
        case .rightHalf:
            return r([cols(1, 1, of: 2), cols(1, 2, of: 3), cols(2, 1, of: 3)][cycle], full)
        case .topHalf: return r(cols(0, 1, of: 1), rows(0, 1, of: 2))
        case .bottomHalf: return r(cols(0, 1, of: 1), rows(1, 1, of: 2))
        case .topLeft: return r(cols(0, 1, of: 2), rows(0, 1, of: 2))
        case .topRight: return r(cols(1, 1, of: 2), rows(0, 1, of: 2))
        case .bottomLeft: return r(cols(0, 1, of: 2), rows(1, 1, of: 2))
        case .bottomRight: return r(cols(1, 1, of: 2), rows(1, 1, of: 2))
        case .firstThird: return r(cols(0, 1, of: 3), full)
        case .centerThird: return r(cols(1, 1, of: 3), full)
        case .lastThird: return r(cols(2, 1, of: 3), full)
        case .firstTwoThirds: return r(cols(0, 2, of: 3), full)
        case .lastTwoThirds: return r(cols(1, 2, of: 3), full)
        case .maximize: return a
        case .center:
            let w = min(window.width, a.width), h = min(window.height, a.height)
            return CGRect(x: (a.midX - w / 2).rounded(), y: (a.midY - h / 2).rounded(), width: w, height: h)
        }
    }
}
