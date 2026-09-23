import Foundation

/// Rooms people recognise from their own day. Typing one of these names as a new room
/// fills in what it's about, so you don't start from an empty room.
public struct RoomTemplate: Sendable, Equatable {
    public let name: String
    public let aliases: [String]
    public let kind: String
    public let about: String

    public static let all: [RoomTemplate] = [
        RoomTemplate(name: "Morning", aliases: ["start", "coffee", "am"], kind: "Daily",
                     about: "Start of the day: email inbox, calendar, messages (Teams, Slack, WhatsApp), news, notes and to-do lists."),
        RoomTemplate(name: "Deep Work", aliases: ["focus", "deep"], kind: "Focus",
                     about: "One focused task: the code editor or writing app and the documents and references for it. No chat, email or social media."),
        RoomTemplate(name: "Design", aliases: ["figma", "ui"], kind: "Work",
                     about: "Design work: Figma files, design references and inspiration, design system docs, Claude or ChatGPT for copy."),
        RoomTemplate(name: "Build", aliases: ["code", "dev", "ship"], kind: "Work",
                     about: "Coding: Cursor or VS Code, Terminal, localhost previews, GitHub, developer docs, Claude or ChatGPT."),
        RoomTemplate(name: "Meetings", aliases: ["call", "calls", "meet"], kind: "Work",
                     about: "Calls: Teams, Zoom or Google Meet, meeting notes (Notes, Notion), the agenda document and calendar."),
        RoomTemplate(name: "Write", aliases: ["writing", "draft"], kind: "Focus",
                     about: "Writing: Paper, Notion, Google Docs or iA Writer, with research tabs and references."),
        RoomTemplate(name: "Learn", aliases: ["inspo", "study"], kind: "Inspiration",
                     about: "Learning and inspiration: YouTube talks, courses, the X feed, newsletters and articles."),
        RoomTemplate(name: "Admin", aliases: ["bills", "life admin"], kind: "Personal",
                     about: "Life admin: bills, banking, taxes, forms, spreadsheets and the email about them."),
        RoomTemplate(name: "Wind Down", aliases: ["evening", "night", "relax"], kind: "Personal",
                     about: "Evening: music (Spotify), messages with friends and family, journaling, a show or a film."),
        RoomTemplate(name: "Hobby", aliases: ["knitting", "craft"], kind: "Personal",
                     about: "A hobby project: tutorials, patterns, Pinterest boards, notes, shopping lists and the files for it."),
    ]

    /// The template a typed name refers to, if any ("morning", "Deep work", "evening").
    public static func matching(_ name: String) -> RoomTemplate? {
        let n = Matcher.fold(name).trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        return all.first { t in Matcher.fold(t.name) == n || t.aliases.contains { Matcher.fold($0) == n } }
    }
}
