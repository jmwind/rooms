import CoreGraphics
import Foundation
import Testing
@testable import RoomsCore

private let screen = CGRect(x: 0, y: 33, width: 1728, height: 1084)
private let g = Tiler.gap
private let a = screen.insetBy(dx: g, dy: g)

@Test func halvesMeetWithOneGap() {
    let l = SnapAction.leftHalf.rect(in: screen), r = SnapAction.rightHalf.rect(in: screen)
    #expect(l.minX == a.minX && r.maxX == a.maxX)
    #expect(r.minX - l.maxX == g)
    #expect(abs(l.width - r.width) <= 1 && l.height == a.height)
}

@Test func leftHalfCyclesHalfTwoThirdsThird() {
    let w = [0, 1, 2].map { SnapAction.leftHalf.rect(in: screen, step: $0).width }
    #expect(w[1] > w[0] && w[0] > w[2])
    #expect(SnapAction.leftHalf.rect(in: screen, step: 3) == SnapAction.leftHalf.rect(in: screen, step: 0))
}

@Test func thirdsAreEqualAndTwoThirdsSpanThem() {
    let t = [SnapAction.firstThird, .centerThird, .lastThird].map { $0.rect(in: screen) }
    #expect((t.map(\.width).max()! - t.map(\.width).min()!) <= 1)   // 1664 pt doesn't split evenly in three
    #expect(t[1].minX - t[0].maxX == g && t[2].minX - t[1].maxX == g)
    let two = SnapAction.firstTwoThirds.rect(in: screen)
    #expect(two.minX == t[0].minX && abs(two.maxX - t[1].maxX) <= 1)
    #expect(abs(SnapAction.lastTwoThirds.rect(in: screen).minX - t[1].minX) <= 1)
}

@Test func quartersTileTheScreen() {
    let q = [SnapAction.topLeft, .topRight, .bottomLeft, .bottomRight].map { $0.rect(in: screen) }
    #expect(q[1].minX - q[0].maxX == g && q[2].minY - q[0].maxY == g)
    #expect(q[3].maxX == a.maxX && q[3].maxY == a.maxY)
}

@Test func maximizeKeepsTheMargins() { #expect(SnapAction.maximize.rect(in: screen) == a) }

@Test func centerKeepsSizeAndCentres() {
    let c = SnapAction.center.rect(in: screen, window: CGSize(width: 800, height: 600))
    #expect(c.size == CGSize(width: 800, height: 600))
    #expect(abs(c.midX - a.midX) <= 1 && abs(c.midY - a.midY) <= 1)
    #expect(SnapAction.center.rect(in: screen, window: CGSize(width: 5000, height: 5000)).size == a.size)
}

@Test func layoutRememberedPerDisplay() throws {
    var room = Room(name: "Design", layout: .auto)
    room.layoutByDisplay["LAPTOP"] = .stack
    #expect(room.layout(on: "LAPTOP") == .stack)
    #expect(room.layout(on: "MONITOR") == .auto)
    #expect(room.layout(on: nil) == .auto)
    let data = try JSONEncoder().encode(RoomsFile(rooms: [room]))
    #expect(try JSONDecoder().decode(RoomsFile.self, from: data).rooms[0].layout(on: "LAPTOP") == .stack)
}
