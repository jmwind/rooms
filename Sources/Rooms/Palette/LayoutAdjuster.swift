import AppKit
import RoomsCore

/// Manual resize mode (⇧Tab in the palette): the separators of the room's layout light
/// up one at a time, the arrow keys move the lit one, and the result is kept as My
/// Layout. It works on the preview alone; nothing moves until you walk into the room.
@MainActor
final class LayoutAdjuster {
    private struct Session {
        let room: Room
        let screen: ScreenInfo
        /// Every window of the room, open, in the room's order.
        let placements: [WindowEngine.Placement]
        let mins: [CGSize]
        var cells: [GridCell]
        var frames: [CGRect]
        var separators: [Separator]
        var current = 0
        var changed = false
    }

    private var session: Session?

    var isAdjusting: Bool { session != nil }

    /// Starts on `room` as it would be laid out now. Returns why it can't, or nil.
    func begin(_ room: Room, snapshot: WindowEngine.Snapshot, engine: WindowEngine) -> String? {
        let uuid = engine.activeScreenUUID()
        guard let screen = snapshot.screens.first(where: { $0.uuid == uuid }) ?? snapshot.screens.first else {
            return "No display to lay out on."
        }
        let (placements, missing) = engine.plan(room, in: snapshot)
        guard missing.isEmpty, placements.count == room.windows.count else {
            let names = Array(Set(missing.map { $0.app ?? $0.bundleID })).sorted().joined(separator: ", ")
            return "Open \(names) first: every window of the room has a place in My Layout."
        }
        guard placements.count > 1 else { return "One window fills the screen; there's nothing to adjust." }
        let kind = room.layout(on: screen.uuid)
        let mins = placements.map { engine.minimumSize(for: $0.window.bundleID) }
        let rects = placements.map(\.rect)
        // My Layout keeps its own cells (reading them back from the frames would lose a
        // fine adjustment); any other tidy layout is read onto the grid as it is.
        let stored = placements.compactMap(\.slot.cell)
        let cells: [GridCell]?
        if kind == .mine, stored.count == placements.count, GridLayout.frames(stored, in: screen.visible, mins: mins) == rects {
            cells = stored
        } else {
            cells = GridLayout.cells(for: rects, in: screen.visible, snapping: GridLayout.units)
        }
        guard let cells else { return "\(kind.title) overlaps windows on purpose. Press Tab for a tidy layout first." }
        let separators = Separators.find(in: cells)
        guard !separators.isEmpty else { return "There's nothing to adjust." }
        session = Session(room: room, screen: screen, placements: placements, mins: mins, cells: cells,
                          frames: GridLayout.frames(cells, in: screen.visible, mins: mins), separators: separators)
        Log.file("Adjusting \(room.name) by hand: \(kind.rawValue), \(separators.count) separators")
        return nil
    }

    /// Lights the next separator.
    func next() {
        guard var s = session else { return }
        s.current = (s.current + 1) % s.separators.count
        session = s
    }

    /// Moves the lit separator by `dx` grid units if it's vertical, `dy` if horizontal.
    /// False when it can't go there: a window would get too small, or an app that
    /// won't shrink holds the line.
    func move(dx: Int, dy: Int) -> Bool {
        guard var s = session else { return false }
        let sep = s.separators[s.current]
        let delta = sep.axis == .vertical ? dx : dy
        guard delta != 0, let cells = Separators.move(sep, by: delta, in: s.cells) else { return false }
        let frames = GridLayout.frames(cells, in: s.screen.visible, mins: s.mins)
        // Refused when the result isn't tidy, or when nothing visibly moved (an app's
        // minimum size kept the line where it was): a key that seems to do nothing
        // should say so, and pressing it again mustn't pile up invisible changes.
        let touched = sep.before + sep.after
        guard Tiler.isClean(frames, in: s.screen.visible.insetBy(dx: Tiler.gap - 1, dy: Tiler.gap - 1)),
              touched.contains(where: { frames[$0] != s.frames[$0] }) else { return false }
        s.cells = cells
        s.frames = frames
        s.changed = true
        // The line may touch other windows now: find the separators again, stay on this one.
        s.separators = Separators.find(in: cells)
        s.current = s.separators.firstIndex { $0.axis == sep.axis && $0.line == sep.line + delta && Set($0.before).isSuperset(of: sep.before) }
            ?? min(s.current, s.separators.count - 1)
        session = s
        return true
    }

    /// The room's windows where they'd go now, for the preview. Nil when `room` isn't
    /// the one being adjusted.
    func placements(for room: Room) -> [WindowEngine.Placement]? {
        guard let s = session, s.room.id == room.id else { return nil }
        return zip(s.placements, s.frames).map { WindowEngine.Placement(slot: $0.slot, rect: $1, window: $0.window) }
    }

    /// Where the lit separator is (AX coordinates).
    var highlight: CGRect? {
        guard let s = session else { return nil }
        return Separators.rect(of: s.separators[s.current], frames: s.frames)
    }

    /// The palette's footer while adjusting.
    var hint: String {
        guard let s = session else { return "" }
        let keys = s.separators[s.current].axis == .vertical ? "← →" : "↑ ↓"
        return "Separator \(s.current + 1) of \(s.separators.count)    \(keys) Move    ⇧ Bigger steps    ⇥ Next    ⇧⇥ Keep"
    }

    /// Leaves manual mode. With `keep`, the room with the adjusted layout as My Layout
    /// on this display; nil when nothing changed, or when discarding.
    func end(keep: Bool) -> Room? {
        defer { session = nil }
        guard let s = session, keep, s.changed else { return nil }
        var room = s.room
        for (i, cell) in s.cells.enumerated() where room.windows.indices.contains(i) { room.windows[i].cell = cell }
        room.layoutByDisplay[s.screen.uuid] = .mine
        return room
    }
}
