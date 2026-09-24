import CoreGraphics
import Testing
@testable import RoomsCore

@Test func emptyLayoutsDoNotFit() {
    for kind in LayoutKind.allCases {
        #expect(!Tiler.fits(count: 0, kind: kind, in: CGRect(x: 0, y: 0, width: 1440, height: 900)))
    }
}

@Test func clampAlsoReturnsWindowsFromAboveAndLeft() {
    let area = CGRect(x: 100, y: 100, width: 1000, height: 800)
    #expect(Tiler.clamp(CGRect(x: -200, y: -100, width: 500, height: 400), into: area)
            == CGRect(x: 100, y: 100, width: 500, height: 400))
}

@Test func gridRejectsNonfiniteFrames() {
    let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
    #expect(GridLayout.cells(for: [.infinite], in: area) == nil)
    #expect(GridLayout.cells(for: [CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)], in: area) == nil)
    #expect(GridLayout.cells(for: [area], in: .infinite) == nil)
    #expect(GridLayout.cells(for: [CGRect(x: 1e30, y: 0, width: 100, height: 100)], in: area) == nil)
}

@Test func fillingHolesDoesNotGrowAcrossDiagonalNeighbour() {
    let cells = [GridCell(col: 1, cols: 1, row: 1, rows: 1), GridCell(col: 0, cols: 1, row: 0, rows: 1)]
    let filled = GridLayout.fillingHoles(cells)
    let rects = filled.map { CGRect(x: $0.col, y: $0.row, width: $0.cols, height: $0.rows) }
    #expect(rects[0].intersection(rects[1]).isEmpty)
}

@Test func malformedSavedCellsFallBackToAuto() {
    let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
    for cell in [GridCell(col: -1, cols: 40, row: 0, rows: 120),
                 GridCell(col: 0, cols: 0, row: 0, rows: 0),
                 GridCell(col: Int.max, cols: Int.max, row: 0, rows: 1)] {
        #expect(GridLayout.fillingHoles([cell]) == [cell])
        #expect(GridLayout.frames([cell], in: area) == Tiler.frames(count: 1, kind: .auto, in: area))
    }
}

@Test func requestedScreenAndMinimumSizeMatrix() {
    let sizes = [CGSize(width: 900, height: 600), CGSize(width: 500, height: 375),
                 CGSize(width: 640, height: 480), CGSize(width: 600, height: 400),
                 CGSize(width: 360, height: 360), CGSize(width: 480, height: 600)]
    for screen in [CGSize(width: 1440, height: 900), CGSize(width: 1728, height: 1117), CGSize(width: 3360, height: 1418)] {
        let area = CGRect(origin: .zero, size: screen)
        for n in 1...10 {
            for seed in 0..<60 {
                var value = UInt64(seed + n * 7919)
                let mins = (0..<n).map { _ in
                    value = value &* 6364136223846793005 &+ 1442695040888963407
                    return sizes[Int((value >> 33) % UInt64(sizes.count))]
                }
                for kind in [LayoutKind.auto, .focus, .columns, .grid, .stack] {
                    let frames = Tiler.frames(count: n, kind: kind, in: area, mins: mins)
                    #expect(frames.count == n)
                    let tidy = kind == .auto ? Tiler.autoKind(count: n, in: area, mins: mins) != .stack
                        : kind != .stack && Tiler.fits(count: n, kind: kind, in: area, mins: mins)
                    if tidy || kind == .auto || kind == .stack {
                        #expect(frames.allSatisfy { area.contains($0) })
                    }
                    if tidy {
                        for i in frames.indices { for j in frames.indices where i < j {
                            #expect(frames[i].intersection(frames[j]).isEmpty)
                        } }
                    }
                }
            }
        }
    }
}
