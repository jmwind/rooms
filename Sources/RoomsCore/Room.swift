import Foundation

/// A project you can walk into: a name you type, and the apps that belong to it.
public struct Room: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Other names that should find this room ("ds", "folio").
    public var aliases: [String]
    /// A short label shown under the name ("Work", "Side project").
    public var kind: String?
    /// What the room is about, in your words.
    public var about: String?
    public var apps: [AppRef]
    /// Specific windows and where they go. Empty for app-only rooms.
    /// The first window is the one you land in.
    public var windows: [WindowSlot]
    /// How the windows are arranged. New rooms are tidied automatically.
    public var layout: LayoutKind
    /// Direct key: 1 means ⌃⌥1. Nil for rooms without one.
    public var shortcut: Int?
    /// A layout chosen for one display (by display UUID), like Moom's per-monitor
    /// layouts: Stack on the laptop, Focus on the monitor. Falls back to `layout`.
    public var layoutByDisplay: [String: LayoutKind]

    public func layout(on display: String?) -> LayoutKind {
        display.flatMap { layoutByDisplay[$0] } ?? layout
    }

    public init(id: String? = nil, name: String, aliases: [String] = [], kind: String? = nil, apps: [AppRef] = [], windows: [WindowSlot] = [], layout: LayoutKind = .auto) {
        self.id = id ?? Room.slug(name)
        self.name = name
        self.aliases = aliases
        self.kind = kind
        self.apps = apps
        self.windows = windows
        self.layout = layout
        self.layoutByDisplay = [:]
    }

    // Only `name` is required, so rooms.json stays easy to write by hand.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Room.slug(name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        about = try c.decodeIfPresent(String.self, forKey: .about)
        apps = try c.decodeIfPresent([AppRef].self, forKey: .apps) ?? []
        windows = try c.decodeIfPresent([WindowSlot].self, forKey: .windows) ?? []
        layout = try c.decodeIfPresent(LayoutKind.self, forKey: .layout) ?? .auto
        shortcut = try c.decodeIfPresent(Int.self, forKey: .shortcut)
        layoutByDisplay = try c.decodeIfPresent([String: LayoutKind].self, forKey: .layoutByDisplay) ?? [:]
    }

    /// Rooms that get ⌃⌥1…9: the ones you gave a number, or else the first nine.
    public static func withShortcuts(_ rooms: [Room]) -> [Int: Room] {
        var map: [Int: Room] = [:]
        if rooms.contains(where: { $0.shortcut != nil }) {
            for room in rooms { if let n = room.shortcut, (1...9).contains(n), map[n] == nil { map[n] = room } }
        } else {
            for (i, room) in rooms.prefix(9).enumerated() { map[i + 1] = room }
        }
        return map
    }

    public static func slug(_ s: String) -> String {
        Matcher.fold(s)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }
}

/// An app that belongs to a room, by bundle identifier.
public struct AppRef: Codable, Hashable, Sendable {
    public var bundleID: String
    /// Only for people reading rooms.json; the app's real name comes from macOS.
    public var name: String?

    public init(_ bundleID: String, name: String? = nil) {
        self.bundleID = bundleID
        self.name = name
    }

    // Accepts either "com.figma.Desktop" or {"bundleID": "com.figma.Desktop", "name": "Figma"}.
    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            bundleID = s
            name = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}

/// The on-disk format of rooms.json.
public struct RoomsFile: Codable, Sendable {
    /// 1: My Layout on a 12-column grid. 2: on `GridLayout.units` columns.
    public static let currentVersion = 2

    public var version: Int
    public var rooms: [Room]

    public init(version: Int = currentVersion, rooms: [Room]) {
        self.version = version
        self.rooms = rooms
    }

    /// The file as the current version reads it: cells from a version 1 file are
    /// brought up to the finer grid, so the layout draws exactly as before.
    public var upgraded: RoomsFile {
        guard version < 2 else { return self }
        var file = self
        for r in file.rooms.indices {
            for w in file.rooms[r].windows.indices {
                if let cell = file.rooms[r].windows[w].cell {
                    file.rooms[r].windows[w].cell = GridLayout.scaled(cell, from: 12)
                }
            }
        }
        file.version = Self.currentVersion
        return file
    }
}
