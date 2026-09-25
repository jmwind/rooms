import CoreGraphics
import Foundation

/// The geometry of the ring of rooms in ⌥Space: where each card sits when the ring
/// is turned to `scroll`, and how the ring keeps coming round for ever.
///
/// Kept here, away from AppKit, because a ring has two mistakes in it that are easy
/// to make and hard to see: a gap where a card should be standing, and a ring that
/// runs out of cards after a lap or two of turning the same way. Both are covered by
/// tests in `RingTests`.
///
/// Distances are in cards (1 is the next room round) and positions in card widths,
/// so the same numbers work whatever size the cards are drawn at.
public struct Ring: Sendable {
    /// How many rooms are on the ring.
    public let count: Int
    /// The angle from one card to the next.
    public let step: CGFloat
    /// How far round the ring a card still shows, in cards.
    public let span: CGFloat
    /// The ring's radius, and how far in front of it you stand.
    public let radius: CGFloat
    public let eye: CGFloat
    /// How far the sphere falls away under the cards to the side.
    public let bulge: CGFloat
    /// How much a card lies back as it goes round, in radians per radian.
    public let tilt: CGFloat

    /// The defaults are the shape Rooms draws: the room you're on square in front of
    /// you, the next and the previous turned away far enough to read as a sphere and
    /// to run off the sides of the screen, and nothing else in the way.
    public init(count: Int, step: CGFloat = 0.46, span: CGFloat = 1.6, radius: CGFloat = 1.7,
                eye: CGFloat = 1.8, bulge: CGFloat = 0.45, tilt: CGFloat = 0.34) {
        self.count = count
        self.step = step
        self.span = span
        self.radius = radius
        self.eye = eye
        self.bulge = bulge
        self.tilt = tilt
    }

    /// Where a card stands on the sphere.
    public struct Spot: Equatable, Sendable {
        /// How far round from the middle, in cards; negative is to the left.
        public let away: CGFloat
        /// How far round in radians, which is also how far the card is turned.
        public let angle: CGFloat
        /// Sideways, up and away from you, in card widths.
        public let x, y, z: CGFloat
        /// 1 for the card you're on, 0 for one at the edge of the ring.
        public let presence: CGFloat
    }

    /// Where the card `away` cards round from the middle sits, or nil when it's far
    /// enough round to be no use drawing.
    public func spot(away: CGFloat) -> Spot? {
        guard abs(away) <= span else { return nil }
        let angle = away * step
        return Spot(
            away: away,
            angle: angle,
            x: radius * sin(angle),
            y: -bulge * (1 - cos(angle)),
            z: radius * (cos(angle) - 1),
            presence: max(0, min(1, (span - abs(away)) / max(0.0001, span - 1)))
        )
    }

    /// How far card `index` is from the middle when the ring is turned to `scroll`,
    /// the short way round. `turn` asks for that card a whole lap on or back, which
    /// is how one card stands on both sides of a ring with only a room or two on it.
    public func away(_ index: Int, scroll: CGFloat, turn: Int = 0) -> CGFloat {
        Self.short(CGFloat(index) - scroll, count: count) + CGFloat(turn * count)
    }

    /// How many times a card has to be drawn: once, unless the ring is so short that
    /// the same room shows on both sides of you at the same time.
    public func turns(for index: Int) -> [Int] {
        guard count > 1 else { return [0] }
        return CGFloat(count) <= 2 * span + 1 ? [-1, 0, 1] : [0]
    }

    /// Where to turn to for `index` from where the ring is now: the short way, and
    /// always landing squarely on a card. Turning from the last room to the first is
    /// one step on, not a rush all the way back.
    public func target(_ index: Int, scroll: CGFloat) -> CGFloat {
        let from = scroll.rounded()
        return from + Self.short(CGFloat(index) - from, count: count)
    }

    /// Once the ring has stopped, brings it back inside one lap. Without this,
    /// turning the same way for long enough carries the ring off into the distance
    /// and leaves you looking at nothing.
    public func settled(_ scroll: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let n = CGFloat(count)
        return (scroll.truncatingRemainder(dividingBy: n) + n).truncatingRemainder(dividingBy: n)
    }

    /// Which room is in the middle when the ring is turned to `scroll`.
    public func middle(at scroll: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let n = CGFloat(count)
        let rounded = (scroll.rounded().truncatingRemainder(dividingBy: n) + n).truncatingRemainder(dividingBy: n)
        return Int(rounded) % count
    }

    /// The shortest signed way round: with five rooms, four on is really one back.
    /// Half a lap either way is counted as forward, so the answer never wobbles
    /// between two equally long ways round.
    static func short(_ delta: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let n = CGFloat(count)
        var d = delta.truncatingRemainder(dividingBy: n)
        if d > n / 2 { d -= n }
        if d <= -n / 2 { d += n }
        return d
    }
}
