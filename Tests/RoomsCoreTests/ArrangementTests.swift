import CoreGraphics
import Testing
@testable import RoomsCore

private let area = CGRect(x: 0, y: 25, width: 2560, height: 1390)

@Test func recognisesColumnsDraggedRoughly() {
    // Three windows dragged into rough thirds, a few points off.
    let exact = Tiler.frames(count: 3, kind: .columns, in: area)
    let rough = exact.map { $0.offsetBy(dx: 12, dy: -9).insetBy(dx: 6, dy: 4) }
    let r = Arrangement.read(rough, in: area)
    #expect(r.kind == .columns)
    #expect(r.order == [0, 1, 2])
}

@Test func whoeverIsInTheBigSpotBecomesTheMainWindow() {
    // Focus layout, but the third window is the one on the left.
    let f = Tiler.frames(count: 3, kind: .focus, in: area)
    let r = Arrangement.read([f[1], f[2], f[0]], in: area)
    #expect(r.kind == .focus)
    #expect(r.order.first == 2)
    #expect(Set(r.order) == [0, 1, 2])
}

@Test func aCustomSideBySideArrangementBecomesMyLayout() {
    let custom = [CGRect(x: 100, y: 200, width: 700, height: 500),
                  CGRect(x: 900, y: 120, width: 1100, height: 1200),
                  CGRect(x: 300, y: 800, width: 500, height: 400)]
    let r = Arrangement.read(custom, in: area)
    #expect(r.kind == .mine)            // not a standard layout, but side by side: snapped to the grid
    #expect(r.order == [0, 1, 2])
    #expect(r.cells?.count == 3)
}

@Test func recognisesAStack() {
    let s = Tiler.frames(count: 4, kind: .stack, in: area)
    #expect(Arrangement.read(s, in: area).kind == .stack)
}

// MARK: A hand-made room: three thirds on top, ⅔ + ⅓ below

private func roomByHand(_ a: CGRect) -> [CGRect] {
    // Dragged by hand: roughly right, gaps a bit uneven.
    let w = a.width, h = a.height
    return [CGRect(x: a.minX + 10, y: a.minY + 12, width: w / 3 - 22, height: h / 2 - 20),
            CGRect(x: a.minX + w / 3 + 4, y: a.minY + 8, width: w / 3 - 14, height: h / 2 - 14),
            CGRect(x: a.minX + 2 * w / 3 + 6, y: a.minY + 14, width: w / 3 - 20, height: h / 2 - 22),
            CGRect(x: a.minX + 12, y: a.minY + h / 2 + 6, width: 2 * w / 3 - 24, height: h / 2 - 18),
            CGRect(x: a.minX + 2 * w / 3 + 8, y: a.minY + h / 2 + 10, width: w / 3 - 20, height: h / 2 - 22)]
}

@Test func twoThirdsPlusOneThirdIsNotMistakenForGrid() {
    let r = Arrangement.read(roomByHand(area), in: area)
    #expect(r.kind == .mine)
    #expect(r.cells == [GridCell(col: 0, cols: 40, row: 0, rows: 60), GridCell(col: 40, cols: 40, row: 0, rows: 60),
                        GridCell(col: 80, cols: 40, row: 0, rows: 60), GridCell(col: 0, cols: 80, row: 60, rows: 60),
                        GridCell(col: 80, cols: 40, row: 60, rows: 60)])
}

@Test func myLayoutDrawsEvenGaps() {
    let cells = Arrangement.read(roomByHand(area), in: area).cells!
    let f = GridLayout.frames(cells, in: area)
    let g = Tiler.gap
    #expect(f[1].minX - f[0].maxX == g && f[2].minX - f[1].maxX == g)   // top thirds
    #expect(f[4].minX - f[3].maxX == g)                                 // ⅔ + ⅓
    #expect(f[3].minY - f[0].maxY == g)                                 // between rows
    #expect(f[3].minX == f[0].minX && f[3].maxX == f[1].maxX)           // ⅔ spans two thirds exactly
    #expect(f[4].maxX == f[2].maxX)
}

@Test func myLayoutMovesToAnotherScreen() {
    let cells = Arrangement.read(roomByHand(area), in: area).cells!
    let laptop = CGRect(x: 0, y: 33, width: 1728, height: 1084)
    let f = GridLayout.frames(cells, in: laptop)
    #expect(f.allSatisfy { laptop.contains($0) })
    #expect(f[4].minX - f[3].maxX == Tiler.gap)
}

@Test func overlappingWindowsAreKeptExactly() {
    let cascade = (0..<3).map { CGRect(x: 100 + 40 * $0, y: 100 + 40 * $0, width: 900, height: 700) }
    #expect(Arrangement.read(cascade.map { $0 }, in: area).kind == .saved)
}

@Test func myLayoutMakesRoomForAppsThatWontShrink() {
    // Three windows in a 16:9 slice of a monitor, where one app won't go below 900 wide.
    let region = CGRect(x: 0, y: 0, width: 2366, height: 1331)
    let cells = [GridCell(col: 0, cols: 40, row: 0, rows: 120),    // Paper
                 GridCell(col: 40, cols: 40, row: 0, rows: 120),   // Figma (needs 900)
                 GridCell(col: 80, cols: 40, row: 0, rows: 120)]   // Claude (needs 600)
    let mins = [CGSize(width: 400, height: 300), CGSize(width: 900, height: 600), CGSize(width: 600, height: 400)]
    let f = GridLayout.frames(cells, in: region, mins: mins)
    #expect(f[1].width >= 900 && f[2].width >= 600 && f[0].width >= 400)
    #expect(f[1].minX - f[0].maxX == Tiler.gap && f[2].minX - f[1].maxX == Tiler.gap)  // no overlap, even gaps
    #expect(f.allSatisfy { region.insetBy(dx: -1, dy: -1).contains($0) })
}

@Test func myLayoutWithoutMinimumsIsUnchanged() {
    let region = CGRect(x: 0, y: 0, width: 2366, height: 1331)
    let cells = [GridCell(col: 0, cols: 80, row: 0, rows: 60), GridCell(col: 80, cols: 40, row: 0, rows: 60)]
    #expect(GridLayout.frames(cells, in: region) == GridLayout.frames(cells, in: region, mins: [.zero, .zero]))
}

// MARK: No holes in My Layout

@Test func aGapBetweenWindowsIsFilled() {
    // Two windows on the left with an empty row between them, one on the right.
    let cells = [GridCell(col: 70, cols: 50, row: 0, rows: 120),
                 GridCell(col: 0, cols: 70, row: 60, rows: 60),
                 GridCell(col: 0, cols: 70, row: 0, rows: 50)]
    let filled = GridLayout.fillingHoles(cells)
    let covered = filled.map { $0.cols * $0.rows }.reduce(0, +)
    #expect(covered == GridLayout.units * GridLayout.units)
    #expect(filled[0] == cells[0])
}

@Test func windowsThatDontReachTheEdgeFillTheScreen() {
    let filled = GridLayout.fillingHoles([GridCell(col: 10, cols: 40, row: 10, rows: 100), GridCell(col: 60, cols: 50, row: 0, rows: 110)])
    #expect(filled.map { $0.cols * $0.rows }.reduce(0, +) == GridLayout.units * GridLayout.units)
}
