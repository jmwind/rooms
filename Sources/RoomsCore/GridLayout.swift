import CoreGraphics

/// Where a window sits on the grid: your own combinations (three thirds on top,
/// ⅔ + ⅓ below) kept as proportions and drawn with the same even gaps as every layout.
public struct GridCell: Codable, Hashable, Sendable {
    public var col: Int, cols: Int, row: Int, rows: Int
    public init(col: Int, cols: Int, row: Int, rows: Int) {
        self.col = col; self.cols = cols; self.row = row; self.rows = rows
    }
}

public enum GridLayout {
    /// The grid's resolution: how finely a window's edge can be placed. Ten units make
    /// a twelfth of the screen, the step of the grid layouts.
    public static let units = 120
    /// Reading an arrangement you dragged together snaps to twelfths, which forgives
    /// windows that are roughly, not exactly, in place. Adjusting a layout by keyboard
    /// moves an edge one unit at a time.
    public static let coarse = 12

    /// Snaps windows to the grid. Nil when they overlap (a cascade or a stack isn't a
    /// grid) or a window is too small to place. `snapping`: the resolution to read at,
    /// twelfths for an arrangement made by hand, `units` for one that is already tidy.
    public static func cells(for frames: [CGRect], in area: CGRect, gap: CGFloat = Tiler.gap, snapping resolution: Int = coarse) -> [GridCell]? {
        let a = area.insetBy(dx: gap, dy: gap)
        guard a.width.isFinite, a.height.isFinite, a.minX.isFinite, a.minY.isFinite,
              a.width > 0, a.height > 0, resolution > 0, units % resolution == 0 else { return nil }
        let scale = units / resolution
        func snap(_ v: CGFloat, _ origin: CGFloat, _ length: CGFloat) -> Int {
            Int(max(0, min(CGFloat(resolution), ((v - origin) / length * CGFloat(resolution)).rounded()))) * scale
        }
        // Grid lines run through the middle of the gaps (see `frames`): a window starts
        // half a gap after its first line and ends half a gap before its last.
        let span = CGSize(width: a.width + gap, height: a.height + gap)
        var cells: [GridCell] = []
        for f in frames {
            guard !f.isInfinite, f.minX.isFinite, f.maxX.isFinite, f.minY.isFinite, f.maxY.isFinite else { return nil }
            let c0 = snap(f.minX, a.minX, span.width), c1 = snap(f.maxX + gap, a.minX, span.width)
            let r0 = snap(f.minY, a.minY, span.height), r1 = snap(f.maxY + gap, a.minY, span.height)
            guard c1 > c0, r1 > r0 else { return nil }
            cells.append(GridCell(col: c0, cols: c1 - c0, row: r0, rows: r1 - r0))
        }
        for i in cells.indices { for j in cells.indices where i < j {
            let x = cells[i].col < cells[j].col + cells[j].cols && cells[j].col < cells[i].col + cells[i].cols
            let y = cells[i].row < cells[j].row + cells[j].rows && cells[j].row < cells[i].row + cells[i].rows
            if x && y { return nil }
        } }
        return fillingHoles(cells)
    }

    /// Grows windows into empty grid space beside them, so a layout never keeps a gap
    /// that was only there because the windows weren't quite touching.
    public static func fillingHoles(_ cells: [GridCell]) -> [GridCell] {
        guard isValid(cells) else { return cells }
        var cells = cells
        func free(_ col: Int, _ row: Int, except i: Int) -> Bool {
            guard (0..<units).contains(col), (0..<units).contains(row) else { return false }
            return !cells.indices.contains { j in
                j != i && col >= cells[j].col && col < cells[j].col + cells[j].cols && row >= cells[j].row && row < cells[j].row + cells[j].rows
            }
        }
        var grew = true
        while grew {
            grew = false
            for i in cells.indices {
                let c = cells[i]
                let rows = c.row..<(c.row + c.rows)
                if rows.allSatisfy({ free(c.col - 1, $0, except: i) }) { cells[i].col -= 1; cells[i].cols += 1; grew = true }
                if rows.allSatisfy({ free(c.col + c.cols, $0, except: i) }) { cells[i].cols += 1; grew = true }
                // Include newly grown columns when checking the corners.
                let cols = cells[i].col..<(cells[i].col + cells[i].cols)
                if cols.allSatisfy({ free($0, c.row - 1, except: i) }) { cells[i].row -= 1; cells[i].rows += 1; grew = true }
                if cols.allSatisfy({ free($0, c.row + c.rows, except: i) }) { cells[i].rows += 1; grew = true }
            }
        }
        return cells
    }

    /// Every cell on the grid, with some size.
    static func isValid(_ cells: [GridCell]) -> Bool {
        cells.allSatisfy { c in
            (0..<units).contains(c.col) && (0..<units).contains(c.row)
                && c.cols > 0 && c.cols <= units - c.col
                && c.rows > 0 && c.rows <= units - c.row
        }
    }

    /// A cell kept on a coarser grid, brought up to `units` (rooms.json before version 2).
    static func scaled(_ c: GridCell, from resolution: Int) -> GridCell {
        let k = units / resolution
        return GridCell(col: c.col * k, cols: c.cols * k, row: c.row * k, rows: c.rows * k)
    }

    /// Draws cells with exactly one `gap` between neighbours and around the edge.
    /// `mins`: each window's smallest size. Columns and rows holding a window that
    /// won't shrink are widened, and the others give up the space, so nothing overlaps.
    public static func frames(_ cells: [GridCell], in area: CGRect, gap: CGFloat = Tiler.gap, mins: [CGSize] = []) -> [CGRect] {
        guard isValid(cells) else {
            return Tiler.frames(count: cells.count, kind: .auto, in: area, gap: gap, mins: mins)
        }
        let a = area.insetBy(dx: gap, dy: gap)
        let mins = mins.count == cells.count ? mins : Array(repeating: .zero, count: cells.count)
        let cells = fillingHoles(cells)   // rooms saved before holes were filled

        // Grid lines run through the middle of the gaps: a window starts half a gap
        // after its first line and ends half a gap before its last, so neighbours are
        // exactly one gap apart and windows at the edge start at the edge. The lines
        // share the area plus one gap (half a gap outside each side).
        // What each column and row must be at least, spreading a window's minimum (plus
        // the gap it gives back) across the columns (or rows) it spans.
        var colMin = [CGFloat](repeating: 0, count: units), rowMin = colMin
        for (c, m) in zip(cells, mins) {
            if m.width > 0 {
                let perCol = (m.width + gap) / CGFloat(c.cols)
                for i in c.col..<min(units, c.col + c.cols) { colMin[i] = max(colMin[i], perCol) }
            }
            if m.height > 0 {
                let perRow = (m.height + gap) / CGFloat(c.rows)
                for i in c.row..<min(units, c.row + c.rows) { rowMin[i] = max(rowMin[i], perRow) }
            }
        }
        let widths = Tiler.distribute(a.width + gap, gap: 0, mins: colMin, weights: Array(repeating: 1, count: units), rounded: false)
        let heights = Tiler.distribute(a.height + gap, gap: 0, mins: rowMin, weights: Array(repeating: 1, count: units), rounded: false)
        func line(_ sizes: [CGFloat], _ start: CGFloat, _ index: Int) -> CGFloat {
            start - gap / 2 + sizes.prefix(index).reduce(0, +)
        }
        return cells.map { c in
            let x0 = line(widths, a.minX, c.col) + gap / 2, x1 = line(widths, a.minX, c.col + c.cols) - gap / 2
            let y0 = line(heights, a.minY, c.row) + gap / 2, y1 = line(heights, a.minY, c.row + c.rows) - gap / 2
            // Round edges, not sizes, so gaps stay exact.
            return CGRect(x: x0.rounded(), y: y0.rounded(), width: x1.rounded() - x0.rounded(), height: y1.rounded() - y0.rounded())
        }
    }
}
