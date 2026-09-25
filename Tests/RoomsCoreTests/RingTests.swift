import CoreGraphics
import Foundation
import Testing
@testable import RoomsCore

/// Every card the ring would draw when it's turned to `scroll`, nearest first.
private func drawn(_ ring: Ring, at scroll: CGFloat) -> [(index: Int, away: CGFloat)] {
    var spots: [(index: Int, away: CGFloat)] = []
    for index in 0..<ring.count {
        for turn in ring.turns(for: index) {
            let away = ring.away(index, scroll: scroll, turn: turn)
            if ring.spot(away: away) != nil { spots.append((index, away)) }
        }
    }
    return spots.sorted { abs($0.away) < abs($1.away) }
}

// MARK: The short way round

@Test func theNextRoomIsOneStepOnEvenFromTheLastOne() {
    let ring = Ring(count: 5)
    #expect(ring.away(1, scroll: 0) == 1)
    #expect(ring.away(4, scroll: 0) == -1)      // the last room stands to your left
    #expect(ring.away(0, scroll: 4) == 1)       // and the first one is one step on from it
}

@Test func turningToARoomTakesTheShortWay() {
    let ring = Ring(count: 5)
    #expect(ring.target(0, scroll: 4) == 5)     // one on, not four back
    #expect(ring.target(4, scroll: 0) == -1)    // one back, not four on
    #expect(ring.target(2, scroll: 0) == 2)
}

@Test func halfALapIsAlwaysCountedForward() {
    // With an even number of rooms the two ways round are the same length: the ring
    // has to pick one and stick to it, or a card flickers between both sides.
    let ring = Ring(count: 4)
    #expect(ring.away(2, scroll: 0) == 2)
    #expect(ring.target(2, scroll: 0) == 2)
}

// MARK: Turning for ever

@Test func theRingNeverRunsOutHoweverFarYouTurn() {
    // The bug this test is here for: `scroll` keeps counting up, and a ring that
    // only knows about one lap has nothing left to show after the first.
    for count in 1...12 {
        let ring = Ring(count: count)
        var scroll: CGFloat = 0
        for step in 0..<(count * 8) {           // eight laps, in either direction
            scroll = ring.target(step % count, scroll: scroll)
            scroll = ring.settled(scroll)
            let cards = drawn(ring, at: scroll)
            #expect(!cards.isEmpty, "nothing on the ring after \(step) turns of \(count)")
            // Whatever lap you're on, a card is square in the middle.
            #expect(abs(cards[0].away) < 0.001, "no card in the middle after \(step) turns of \(count)")
            #expect(cards[0].index == step % count)
        }
    }
}

@Test func settlingKeepsTheRingWhereItWas() {
    let ring = Ring(count: 5)
    for lap in -3...3 {
        let scroll = CGFloat(lap * 5 + 2)
        #expect(ring.settled(scroll) == 2)
        #expect(ring.middle(at: scroll) == 2)
    }
}

// MARK: No gaps, no pile-ups

@Test func thereIsAlwaysAPeekOfTheNextRoomAndTheLast() {
    // Turning half way between two rooms is the moment a gap would show.
    for count in 3...12 {
        let ring = Ring(count: count)
        for tenth in 0...(count * 10) {
            let scroll = CGFloat(tenth) / 10
            let cards = drawn(ring, at: scroll)
            #expect(cards.contains { $0.away > 0.3 && $0.away <= ring.span },
                    "no room to the right at \(scroll) of \(count)")
            #expect(cards.contains { $0.away < -0.3 && $0.away >= -ring.span },
                    "no room to the left at \(scroll) of \(count)")
        }
    }
}

@Test func noTwoCardsStandInTheSamePlace() {
    for count in 1...12 {
        let ring = Ring(count: count)
        for tenth in 0...(count * 10) {
            let scroll = CGFloat(tenth) / 10
            let places = drawn(ring, at: scroll).map(\.away).sorted()
            for (a, b) in zip(places, places.dropFirst()) {
                #expect(b - a > 0.5, "two cards at \(a) and \(b) with \(count) rooms")
            }
        }
    }
}

@Test func oneRoomIsDrawnOnceAndTwoRoomsFillBothSides() {
    #expect(Ring(count: 1).turns(for: 0) == [0])
    #expect(drawn(Ring(count: 1), at: 0).count == 1)
    // With two rooms, the other one stands on both sides of you: that's what an
    // endless ring means when there's only one other place to go.
    let two = drawn(Ring(count: 2), at: 0)
    #expect(two.count == 3)
    #expect(two.filter { $0.index == 1 }.count == 2)
}

// MARK: The shape of the sphere

@Test func cardsCurveAwayAndDownAsTheyGoRound() {
    let ring = Ring(count: 9)
    let middle = ring.spot(away: 0)!
    let next = ring.spot(away: 1)!
    #expect(middle.x == 0 && middle.y == 0 && middle.z == 0)
    #expect(middle.presence == 1)
    #expect(next.x > 0.6 && next.x < 0.9)       // far enough over to peek past the middle card
    #expect(next.z < 0)                          // and further away
    #expect(next.y < 0)                          // and lower, on the sphere's surface
    #expect(next.angle > 0.3)                    // turned away from you, not flat on
    // Symmetrical, and gone by the edge of the ring.
    #expect(ring.spot(away: -1)!.x == -next.x)
    #expect(ring.spot(away: -1)!.y == next.y)
    #expect(ring.spot(away: ring.span)!.presence == 0)
    #expect(ring.spot(away: ring.span + 0.01) == nil)
}

@Test func theCardEitherSideKeepsClearOfTheMiddleOne() {
    // A card is one width wide. Its neighbour has to come far enough round to be
    // seen past the middle card, but not so far that it covers it.
    let ring = Ring(count: 9)
    let next = ring.spot(away: 1)!
    let shrink = ring.eye / (ring.eye - next.z)          // how perspective shrinks it
    let seen = next.x * shrink                            // where it lands on screen
    let halfWidth = 0.5 * shrink * cos(next.angle)        // and how wide it looks
    #expect(seen - halfWidth < 0.5)                       // overlaps the middle card: a peek
    #expect(seen - halfWidth > 0.15)                      // but leaves most of it showing
}
