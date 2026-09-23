import Foundation
import os

enum Log {
    private static let subsystem = "com.saragordic.rooms"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let switcher = Logger(subsystem: subsystem, category: "switcher")

    /// ~/Library/Logs/Rooms/rooms.log — a plain file anyone can open (Console.app or
    /// a text editor), so a switch that goes wrong can be explained afterwards.
    static let fileURL: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/Rooms/rooms.log")

    private static let queue = DispatchQueue(label: "rooms.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func file(_ message: String) {
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > 2_000_000 {
                try? fm.removeItem(at: fileURL) // keep it small
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }
}
