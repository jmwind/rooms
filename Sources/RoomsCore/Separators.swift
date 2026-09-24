import CoreGraphics

/// The line between neighbouring windows in My Layout: the windows that end at it on
/// one side and the ones that start at it on the other. Moving it resizes all of them
/// together, so nothing ever overlaps.
public struct Separator: Hashable, Sendable {
    public enum Axis: Hashable, Sendable { case vertical, horizontal }
    public let axis: Axis
    /// The grid line it sits on (1 ..< `GridLayout.units`).
    public let line: Int
    /// Windows (indices into the cells) left of a vertical separator, or above a
    /// horizontal one: they end at the line.
    public let before: [Int]
    /// Windows right of it, or below: they start at the line.
    public let after: [Int]

    public init(axis: Axis, line: Int, before: [Int], after: [Int]) {
        self.axis = axis; self.line = line; self.before = before; self.after = after
    }
}

/// Manual resize mode works on these: ⇧Tab lights one up, the arrow keys move it.
public enum Separators {
    /// A twelfth of the screen in grid units: how far ⇧ + an arrow key moves, and the
    /// least a window keeps when a separator is moved into it.
    public static let twelfth = GridLayout.units / GridLayout.coarse

    /// Every separator in the layout: the vertical ones left to right, then the
    /// horizontal ones top to bottom. Two windows share a separator when one ends and
    /// the other starts on the same line and they sit beside each other; windows joined
    /// through others (a tall window beside two stacked ones) share it too, so the whole
    /// line moves at once and nothing is left overlapping.
    public static func find(in cells: [GridCell]) -> [Separator] {
        var result: [Separator] = []
        for axis in [Separator.Axis.vertical, .horizontal] {
            let start = { (c: GridCell) in axis == .vertical ? c.col : c.row }
            let length = { (c: GridCell) in axis == .vertical ? c.cols : c.rows }
            let across = { (c: GridCell) -> Range<Int> in axis == .vertical ? c.row..<(c.row + c.rows) : c.col..<(c.col + c.cols) }
            for line in 1..<GridLayout.units {
                let ends = cells.indices.filter { start(cells[$0]) + length(cells[$0]) == line }
                let starts = cells.indices.filter { start(cells[$0]) == line }
                guard !ends.isEmpty, !starts.isEmpty else { continue }
                var remaining = Set(ends + starts)
                var groups: [(before: [Int], after: [Int], from: Int)] = []
                while let seed = remaining.min() {
                    remaining.remove(seed)
                    var group = [seed], queue = [seed]
                    while let i = queue.popLast() {
                        let opposite = ends.contains(i) ? starts : ends
                        for j in opposite where remaining.contains(j) && across(cells[i]).overlaps(across(cells[j])) {
                            remaining.remove(j)
                            group.append(j)
                            queue.append(j)
                        }
                    }
                    let before = group.filter(ends.contains).sorted(), after = group.filter(starts.contains).sorted()
                    guard !before.isEmpty, !after.isEmpty else { continue }
                    groups.append((before, after, group.map { across(cells[$0]).lowerBound }.min() ?? 0))
                }
                for g in groups.sorted(by: { $0.from < $1.from }) {
                    result.append(Separator(axis: axis, line: line, before: g.before, after: g.after))
                }
            }
        }
        return result
    }

    /// The layout with `s` moved `delta` units right (or down; negative: left or up).
    /// Nil when a window on either side would get thinner than a twelfth.
    public static func move(_ s: Separator, by delta: Int, in cells: [GridCell]) -> [GridCell]? {
        guard delta != 0, (1..<GridLayout.units).contains(s.line + delta) else { return nil }
        var out = cells
        for i in s.before where cells.indices.contains(i) {
            if s.axis == .vertical { out[i].cols += delta } else { out[i].rows += delta }
        }
        for i in s.after where cells.indices.contains(i) {
            if s.axis == .vertical { out[i].col += delta; out[i].cols -= delta } else { out[i].row += delta; out[i].rows -= delta }
        }
        let thinnest = (s.before + s.after).filter(cells.indices.contains)
            .map { s.axis == .vertical ? out[$0].cols : out[$0].rows }.min() ?? 0
        guard thinnest >= twelfth, GridLayout.isValid(out) else { return nil }
        return out
    }

    /// Where the separator shows: the gap between its windows, along their shared edge.
    /// `frames`: the windows' frames, in the cells' order.
    public static func rect(of s: Separator, frames: [CGRect]) -> CGRect {
        let before = s.before.filter(frames.indices.contains).map { frames[$0] }
        let after = s.after.filter(frames.indices.contains).map { frames[$0] }
        let all = before + after
        guard !before.isEmpty, !after.isEmpty else { return .null }
        if s.axis == .vertical {
            let x0 = before.map(\.maxX).max()!, x1 = after.map(\.minX).min()!
            let y0 = all.map(\.minY).min()!, y1 = all.map(\.maxY).max()!
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        } else {
            let y0 = before.map(\.maxY).max()!, y1 = after.map(\.minY).min()!
            let x0 = all.map(\.minX).min()!, x1 = all.map(\.maxX).max()!
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }
}
