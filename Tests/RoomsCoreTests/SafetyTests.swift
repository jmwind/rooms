import CoreGraphics
import Foundation
import Testing
@testable import RoomsCore

// MARK: Parking never lands on another display

private let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
private let window = CGSize(width: 1000, height: 700)

private func spill(_ origin: CGPoint, onto others: [CGRect]) -> CGFloat {
    let parked = CGRect(origin: origin, size: window)
    return others.reduce(0) { s, o in let x = o.intersection(parked); return s + (x.isNull ? 0 : x.width * x.height) }
}

@Test func parkingAvoidsAMonitorInAnyDirection() {
    let monitors = [
        CGRect(x: -823, y: -1418, width: 3360, height: 1418),   // above (this desk)
        CGRect(x: 1728, y: 0, width: 2560, height: 1440),       // right
        CGRect(x: 0, y: 1117, width: 2560, height: 1440),       // below
        CGRect(x: -2560, y: 0, width: 2560, height: 1440),      // left
    ]
    for monitor in monitors {
        let origin = Geometry.parkingOrigin(windowSize: window, screen: laptop, otherScreens: [monitor])
        #expect(spill(origin, onto: [monitor]) == 0, "\(monitor)")
        // A sliver stays on the laptop, so macOS keeps the window.
        #expect(laptop.intersects(CGRect(origin: origin, size: window)), "\(monitor)")
    }
}

@Test func parkingPicksTheLeastBadCornerWhenBoxedIn() {
    let around = [CGRect(x: 1728, y: -2000, width: 3000, height: 5000), CGRect(x: -3000, y: -2000, width: 3000, height: 5000)]
    let origin = Geometry.parkingOrigin(windowSize: window, screen: laptop, otherScreens: around)
    #expect(laptop.intersects(CGRect(origin: origin, size: window)))
}

// MARK: Ways back stay on a connected display

@Test func aWayBackToAMissingDisplayComesToAConnectedOne() {
    let fromGoneMonitor = CGRect(x: 500, y: -1200, width: 2000, height: 900)
    let back = Geometry.keptOnScreen(fromGoneMonitor, screens: [laptop])
    #expect(laptop.contains(back))
    let onLaptop = CGRect(x: 100, y: 100, width: 800, height: 600)
    #expect(Geometry.keptOnScreen(onLaptop, screens: [laptop]) == onLaptop)
}

// MARK: Clean layouts

@Test func cleanMeansInsideAndNotOverlapping() {
    let a = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    #expect(Tiler.isClean([CGRect(x: 0, y: 0, width: 500, height: 1000), CGRect(x: 500, y: 0, width: 500, height: 1000)], in: a))
    #expect(!Tiler.isClean([CGRect(x: 0, y: 0, width: 600, height: 1000), CGRect(x: 500, y: 0, width: 500, height: 1000)], in: a))
    #expect(!Tiler.isClean([CGRect(x: 600, y: 0, width: 500, height: 1000)], in: a))
}

// MARK: Browser windows: a free one first

@Test func aClosedBrowserWindowIsReplacedByAFreeOneFirst() {
    let slot = WindowSlot(bundleID: "chrome", title: "Project A", windowID: 1, frame: FractionalFrame(x: 0, y: 0, w: 1, h: 1))
    let other = WindowInfo(bundleID: "chrome", title: "Project B", windowID: 20)   // another room's
    let free = WindowInfo(bundleID: "chrome", title: "New Tab", windowID: 30)
    #expect(SlotMatcher.assign(slots: [slot], windows: [other, free], claimed: [20]) == [0: 1])
    // With nothing free, any window of the app still fills it.
    #expect(SlotMatcher.assign(slots: [slot], windows: [other], claimed: [20]) == [0: 0])
}

// MARK: An unreadable ledger is kept aside, not lost

@Test func anUnreadableLedgerIsMovedAside() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appending(path: "resting.json")
    try Data("{ not json".utf8).write(to: url)
    #expect(RestLedger.load(from: url).entries.isEmpty)
    let kept = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("resting.unreadable-") }
    #expect(kept.count == 1)
}

// MARK: No window squeezed to nothing

@Test func anUnknownMinimumIsNeverSqueezedToNothing() {
    // Teams, Granola (minimum not known yet) and WhatsApp (won't go below 970×600)
    // on a laptop with the Dock showing: any layout offered gives Granola a usable
    // size, never the 0-wide Focus that made Tab look broken.
    let laptop = CGRect(x: 0, y: 33, width: 1728, height: 1000)
    let mins = [CGSize(width: 360, height: 360), .zero, CGSize(width: 970, height: 600)]
    for kind in [LayoutKind.focus, .columns, .grid] where Tiler.fits(count: 3, kind: kind, in: laptop, mins: mins) {
        let f = Tiler.frames(count: 3, kind: kind, in: laptop, mins: mins)
        #expect(f[1].width >= Tiler.usable.width - 1 && f[1].height >= Tiler.usable.height - 1, "\(kind): Granola \(f[1])")
    }
    // With Granola measured (500×400) it's the same: the trio needs 1,862 pt across
    // or 1,016 pt of height, and the laptop has 1,696 × 968.
    let measured = [CGSize(width: 360, height: 360), CGSize(width: 500, height: 400), CGSize(width: 970, height: 600)]
    #expect(Tiler.autoKind(count: 3, in: laptop, mins: measured) == .stack)
}

@Test func tidyLayoutsGiveEveryWindowAUsableSize() {
    let laptop = CGRect(x: 0, y: 33, width: 1728, height: 1000)
    for n in 2...8 {
        for kind in [LayoutKind.focus, .columns, .grid] where Tiler.fits(count: n, kind: kind, in: laptop) {
            for r in Tiler.frames(count: n, kind: kind, in: laptop) {
                #expect(r.width >= Tiler.usable.width - 1 && r.height >= Tiler.usable.height - 1, "\(kind) \(n)")
            }
        }
    }
}
