import CoreGraphics

/// Reads an arrangement you made by hand: which layout it's closest to, and which
/// window sits in which spot of that layout.
public enum Arrangement {
    public struct Reading: Sendable, Equatable {
        /// The layout it matches, or `.saved` when it's your own arrangement.
        public let kind: LayoutKind
        /// Window indices in room order for that layout (the main window first).
        public let order: [Int]
        /// The furthest any window is (in points, averaged over its edges) from the layout.
        public let distance: CGFloat
        /// For `.mine`: each window's grid cell, in `order`.
        public var cells: [GridCell]? = nil

        public init(kind: LayoutKind, order: [Int], distance: CGFloat, cells: [GridCell]? = nil) {
            self.kind = kind
            self.order = order
            self.distance = distance
            self.cells = cells
        }
    }

    /// How close counts as "that layout": every window within this many points.
    public static let tolerance: CGFloat = 40

    /// `frames`: where the windows are now (AX space). `area`: the screen's usable area.
    public static func read(_ frames: [CGRect], in area: CGRect, mins: [CGSize] = []) -> Reading {
        let n = frames.count
        let identity = Reading(kind: .saved, order: Array(0..<n), distance: .infinity)
        guard n > 1 else { return Reading(kind: n == 1 ? .focus : .saved, order: Array(0..<n), distance: 0) }
        var best = identity
        for kind in [LayoutKind.focus, .stack, .columns, .grid] {
            let target = Tiler.frames(count: n, kind: kind, in: area, mins: mins.count == n ? mins : [])
            // Which of your windows is in each spot: nearest first, each window once.
            var used = Set<Int>(), order: [Int] = [], worst: CGFloat = 0
            for spot in target {
                guard let w = frames.indices.filter({ !used.contains($0) }).min(by: { gap(frames[$0], spot) < gap(frames[$1], spot) }) else { break }
                used.insert(w)
                order.append(w)
                worst = max(worst, gap(frames[w], spot))
            }
            // Every window has to fit the layout, not just most of them: three perfect
            // thirds must not hide a ⅔ + ⅓ row underneath.
            if worst < best.distance { best = Reading(kind: kind, order: order, distance: worst) }
        }
        if best.distance <= tolerance { return best }
        // Your own combination: snap it to the grid if the windows sit side by side.
        if let cells = GridLayout.cells(for: frames, in: area) {
            return Reading(kind: .mine, order: Array(0..<n), distance: best.distance, cells: cells)
        }
        // Overlapping on purpose: keep it exactly.
        return Reading(kind: .saved, order: Array(0..<n), distance: best.distance)
    }

    /// Average distance between the four edges of two rectangles.
    static func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        (abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.maxX - b.maxX) + abs(a.maxY - b.maxY)) / 4
    }
}
