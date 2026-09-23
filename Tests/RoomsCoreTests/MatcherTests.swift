import Foundation
import Testing
@testable import RoomsCore

private let rooms = [
    Room(name: "Orbit", aliases: ["orb"], kind: "Work"),          // a project with a short alias
    Room(name: "Sample Research Project", aliases: ["sample", "research"], kind: "Work"),
    Room(name: "Reading", aliases: ["books"]),
    Room(name: "Portfolio", aliases: ["folio"]),
    Room(name: "Personal"),
    Room(name: "Side projects", aliases: ["side"]),
]

private func top(_ q: String) -> String? { Matcher.rank(q, rooms: rooms).first?.room.name }

@Test func aliasWins() { #expect(top("orb") == "Orbit") }
@Test func prefixOfName() { #expect(top("orbi") == "Orbit") }
@Test func wordInsideName() { #expect(top("research") == "Sample Research Project") }
@Test func initials() { #expect(top("srp") == "Sample Research Project") }
@Test func severalWords() { #expect(top("sample res") == "Sample Research Project") }
@Test func caseAndSpacing() { #expect(top("  READING ") == "Reading") }
@Test func accentsFold() { #expect(Matcher.fold("Ćevapi Đuveč") == "cevapi djuvec") }
@Test func cyrillicReadsAsLatin() { #expect(Matcher.fold("Привет") == "privet") }
@Test func noMatch() { #expect(Matcher.rank("zzz", rooms: rooms).isEmpty) }

@Test func exactBeatsPrefix() {
    // "p" prefixes both Portfolio and Personal; an exact alias must win outright.
    #expect(top("folio") == "Portfolio")
    #expect(Matcher.rank("p", rooms: rooms).prefix(2).map(\.room.name).sorted() == ["Personal", "Portfolio"])
}

@Test func emptyQueryListsRecentFirst() {
    let recency = ["reading": Date(), "orbit": Date(timeIntervalSinceNow: -60)]
    let names = Matcher.rank("", rooms: rooms, recency: recency).map(\.room.name)
    #expect(names.prefix(2) == ["Reading", "Orbit"])
    #expect(names.count == rooms.count)
}

@Test func recencyBreaksTies() {
    let recency = ["personal": Date()]
    #expect(Matcher.rank("p", rooms: rooms, recency: recency).first?.room.name == "Personal")
}

@Test func roomsJSONIsForgiving() throws {
    let json = #"{"version":1,"rooms":[{"name":"Sample Research Project","apps":["com.microsoft.teams2",{"bundleID":"com.google.Chrome","name":"Chrome"}]}]}"#
    let file = try JSONDecoder().decode(RoomsFile.self, from: Data(json.utf8))
    #expect(file.rooms[0].id == "sample-research-project")
    #expect(file.rooms[0].apps.map(\.bundleID) == ["com.microsoft.teams2", "com.google.Chrome"])
    #expect(file.rooms[0].aliases.isEmpty)
}

@Test func storeRoundTrips() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "rooms-test-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let loaded = try RoomStore.loadOrSeed(at: url) { rooms }
    #expect(loaded == rooms)
}

@Test func templatesMatchNamesAndAliases() {
    #expect(RoomTemplate.matching("morning")?.name == "Morning")
    #expect(RoomTemplate.matching("  Deep work ")?.name == "Deep Work")
    #expect(RoomTemplate.matching("evening")?.name == "Wind Down")
    #expect(RoomTemplate.matching("Orbit") == nil)
    #expect(RoomTemplate.all.allSatisfy { !$0.about.isEmpty })
}
