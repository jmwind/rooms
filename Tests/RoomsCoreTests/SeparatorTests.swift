import CoreGraphics
import Foundation
import Testing
@testable import RoomsCore

private let area = CGRect(x: 0, y: 25, width: 2560, height: 1390)
private let g = Tiler.gap
private let u = GridLayout.units

private func clean(_ frames: [CGRect]) -> Bool {
    Tiler.isClean(frames, in: area.insetBy(dx: g - 1, dy: g - 1))
}

// MARK: Finding separators

@Test func focusHasOneVerticalAndOneHorizontalSeparator() {
    let cells = [GridCell(col: 0, cols: 72, row: 0, rows: u), GridCell(col: 72, cols: 48, row: 0, rows: 60), GridCell(col: 72, cols: 48, row: 60, rows: 60)]
    let s = Separators.find(in: cells)
    #expect(s.count == 2)
    #expect(s[0] == Separator(axis: .vertical, line: 72, before: [0], after: [1, 2]))   // the whole column moves together
    #expect(s[1] == Separator(axis: .horizontal, line: 60, before: [1], after: [2]))
}

@Test func aGridHasOneSeparatorPerSharedEdge() {
    // 2 × 2: the top pair and the bottom pair can be split differently.
    let cells = [GridCell(col: 0, cols: 60, row: 0, rows: 60), GridCell(col: 60, cols: 60, row: 0, rows: 60),
                 GridCell(col: 0, cols: 60, row: 60, rows: 60), GridCell(col: 60, cols: 60, row: 60, rows: 60)]
    let s = Separators.find(in: cells)
    #expect(s.map(\.axis) == [.vertical, .vertical, .horizontal, .horizontal])
    #expect(s[0].before == [0] && s[0].after == [1])
    #expect(s[1].before == [2] && s[1].after == [3])
    #expect(s[2].before == [0] && s[2].after == [2])
    #expect(s[3].before == [1] && s[3].after == [3])
}

@Test func separatorsAreOrderedLeftToRightThenTopToBottom() {
    let cells = [GridCell(col: 0, cols: 40, row: 0, rows: 60), GridCell(col: 40, cols: 40, row: 0, rows: 60),
                 GridCell(col: 80, cols: 40, row: 0, rows: 60), GridCell(col: 0, cols: 80, row: 60, rows: 60),
                 GridCell(col: 80, cols: 40, row: 60, rows: 60)]
    let s = Separators.find(in: cells)
    #expect(s.map { ($0.axis == .vertical ? "v" : "h") + "\($0.line)" } == ["v40", "v80", "v80", "h60", "h60"])
    // Line 80 carries two separators that share no rows (between the top thirds, and
    // between ⅔ and ⅓ below), so each row can be split on its own. Likewise the
    // middle line: ⅔ sits under exactly two thirds, ⅓ under the other.
    #expect(s[1].before == [1] && s[1].after == [2])
    #expect(s[2].before == [3] && s[2].after == [4])
    #expect(s[3].before == [0, 1] && s[3].after == [3])
    #expect(s[4].before == [2] && s[4].after == [4])
}

// MARK: Moving them

@Test func movingASeparatorResizesBothSidesAndStaysTidy() {
    let cells = [GridCell(col: 0, cols: 72, row: 0, rows: u), GridCell(col: 72, cols: 48, row: 0, rows: 60), GridCell(col: 72, cols: 48, row: 60, rows: 60)]
    let s = Separators.find(in: cells)
    let moved = Separators.move(s[0], by: -10, in: cells)!
    #expect(moved[0] == GridCell(col: 0, cols: 62, row: 0, rows: u))
    #expect(moved[1] == GridCell(col: 62, cols: 58, row: 0, rows: 60))
    #expect(moved[2] == GridCell(col: 62, cols: 58, row: 60, rows: 60))
    let before = GridLayout.frames(cells, in: area), after = GridLayout.frames(moved, in: area)
    #expect(clean(after))
    #expect(after[0].width < before[0].width && after[1].width > before[1].width)
    #expect(after[1].minX - after[0].maxX == g)
    // The separator is found again where it now is.
    #expect(Separators.find(in: moved)[0].line == 62)
}

@Test func aSplitRowJoinsTheSeparatorBelowIt() {
    // Move the top pair's split in a 2 × 2 grid: the horizontal line now touches all four
    // windows, so it becomes one separator and can't be moved into an overlap.
    let cells = [GridCell(col: 0, cols: 60, row: 0, rows: 60), GridCell(col: 60, cols: 60, row: 0, rows: 60),
                 GridCell(col: 0, cols: 60, row: 60, rows: 60), GridCell(col: 60, cols: 60, row: 60, rows: 60)]
    let moved = Separators.move(Separators.find(in: cells)[0], by: 10, in: cells)!
    let s = Separators.find(in: moved)
    #expect(s.count == 3)
    #expect(s[2] == Separator(axis: .horizontal, line: 60, before: [0, 1], after: [2, 3]))
    let down = Separators.move(s[2], by: 5, in: moved)!
    #expect(clean(GridLayout.frames(down, in: area)))
    #expect(down[0].rows == 65 && down[3].row == 65 && down[3].rows == 55)
}

@Test func aWindowNeverGetsThinnerThanATwelfth() {
    let cells = [GridCell(col: 0, cols: 60, row: 0, rows: u), GridCell(col: 60, cols: 60, row: 0, rows: u)]
    let s = Separators.find(in: cells)[0]
    #expect(Separators.move(s, by: 50, in: cells) != nil)
    #expect(Separators.move(s, by: 51, in: cells) == nil)
    #expect(Separators.move(s, by: -51, in: cells) == nil)
    #expect(Separators.move(s, by: 0, in: cells) == nil)
    #expect(Separators.twelfth == 10)
}

@Test func everyMoveOfEveryLayoutStaysTidy() {
    // Start from each tidy layout for 2…6 windows, move every separator both ways
    // by big steps, and check nothing overlaps or leaves the screen.
    for n in 2...6 {
        for kind in [LayoutKind.focus, .columns, .grid] {
            guard let cells = GridLayout.cells(for: Tiler.frames(count: n, kind: kind, in: area), in: area, snapping: u) else {
                Issue.record("\(kind) \(n) didn't snap"); continue
            }
            for s in Separators.find(in: cells) {
                for delta in [-Separators.twelfth, Separators.twelfth] {
                    guard let moved = Separators.move(s, by: delta, in: cells) else { continue }
                    #expect(clean(GridLayout.frames(moved, in: area)), "\(kind) \(n) \(s) by \(delta)")
                }
            }
        }
    }
}

// MARK: Where it's drawn

@Test func theSeparatorIsTheGapBetweenItsWindows() {
    let cells = [GridCell(col: 0, cols: 72, row: 0, rows: u), GridCell(col: 72, cols: 48, row: 0, rows: 60), GridCell(col: 72, cols: 48, row: 60, rows: 60)]
    let f = GridLayout.frames(cells, in: area)
    let s = Separators.find(in: cells)
    let v = Separators.rect(of: s[0], frames: f)
    #expect(v.minX == f[0].maxX && v.width == g && v.minY == f[0].minY && v.maxY == f[0].maxY)
    let h = Separators.rect(of: s[1], frames: f)
    #expect(h.minY == f[1].maxY && h.height == g && h.minX == f[1].minX && h.maxX == f[2].maxX)
}

// MARK: Snapping tidy layouts exactly

@Test func tidyLayoutsSnapToTheFineGridWithoutMoving() {
    // Within a few points: Focus gives the main window 60% of the width between the
    // gaps, the grid 60% of its lines (a fifth of a gap apart), nothing you'd notice.
    for n in 2...6 {
        for kind in [LayoutKind.focus, .columns, .grid] {
            let frames = Tiler.frames(count: n, kind: kind, in: area)
            let cells = GridLayout.cells(for: frames, in: area, snapping: u)!
            let back = GridLayout.frames(cells, in: area)
            for (a, b) in zip(frames, back) {
                #expect(abs(a.minX - b.minX) <= 4 && abs(a.maxX - b.maxX) <= 4 && abs(a.minY - b.minY) <= 4 && abs(a.maxY - b.maxY) <= 4, "\(kind) \(n)")
            }
        }
    }
}

@Test func focusHeroSnapsToSixtyPercent() {
    let cells = GridLayout.cells(for: Tiler.frames(count: 3, kind: .focus, in: area), in: area, snapping: u)!
    #expect(cells[0] == GridCell(col: 0, cols: 72, row: 0, rows: u))
}

// MARK: rooms.json from before the finer grid

@Test func version1CellsAreBroughtUpToTheFinerGrid() throws {
    let json = #"{"version":1,"rooms":[{"name":"Design","windows":[{"bundleID":"a","title":"","frame":{"x":0,"y":0,"w":1,"h":1},"cell":{"col":4,"cols":8,"row":0,"rows":6}}]}]}"#
    let file = try JSONDecoder().decode(RoomsFile.self, from: Data(json.utf8)).upgraded
    #expect(file.version == RoomsFile.currentVersion)
    #expect(file.rooms[0].windows[0].cell == GridCell(col: 40, cols: 80, row: 0, rows: 60))
    // Already current: untouched.
    let current = #"{"version":2,"rooms":[{"name":"Design","windows":[{"bundleID":"a","title":"","frame":{"x":0,"y":0,"w":1,"h":1},"cell":{"col":4,"cols":8,"row":0,"rows":6}}]}]}"#
    #expect(try JSONDecoder().decode(RoomsFile.self, from: Data(current.utf8)).upgraded.rooms[0].windows[0].cell == GridCell(col: 4, cols: 8, row: 0, rows: 6))
}

@Test func theStoreUpgradesOnLoadAndSavesTheCurrentVersion() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "rooms-tests-\(UUID().uuidString)")
    let url = dir.appending(path: "rooms.json")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let json = #"{"version":1,"rooms":[{"name":"Design","windows":[{"bundleID":"a","title":"","frame":{"x":0,"y":0,"w":1,"h":1},"cell":{"col":0,"cols":12,"row":0,"rows":12}}]}]}"#
    try Data(json.utf8).write(to: url)
    let rooms = try RoomStore.load(from: url)
    #expect(rooms[0].windows[0].cell == GridCell(col: 0, cols: u, row: 0, rows: u))
    try RoomStore.save(rooms, to: url)
    let saved = try JSONDecoder().decode(RoomsFile.self, from: Data(contentsOf: url))
    #expect(saved.version == 2)
}
