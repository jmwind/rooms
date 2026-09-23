import Foundation

/// Reads and writes rooms.json. The file is meant to be readable and hand-editable.
public enum RoomStore {
    /// ~/Library/Application Support/Rooms/rooms.json
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Rooms", directoryHint: .isDirectory)
            .appending(path: "rooms.json")
    }

    public static func load(from url: URL) throws -> [Room] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RoomsFile.self, from: data).rooms
    }

    public static func save(_ rooms: [Room], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(RoomsFile(rooms: rooms)).write(to: url, options: .atomic)
    }

    /// Loads the file, writing `seed()` first if there is no file yet.
    public static func loadOrSeed(at url: URL, seed: () -> [Room]) throws -> [Room] {
        if !FileManager.default.fileExists(atPath: url.path) {
            try save(seed(), to: url)
        }
        return try load(from: url)
    }

    /// A readable explanation of a decoding failure, for showing in the menu.
    public static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let ctx):
            return (ctx.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String ?? ctx.debugDescription
        case DecodingError.keyNotFound(let key, let ctx):
            return "Missing \"\(key.stringValue)\" at \(path(ctx))"
        case DecodingError.typeMismatch(_, let ctx), DecodingError.valueNotFound(_, let ctx):
            return "\(ctx.debugDescription) at \(path(ctx))"
        default:
            return error.localizedDescription
        }
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
}
