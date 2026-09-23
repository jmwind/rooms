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
    #expect(FileManager.default.fileExists(atPath: dir.appending(path: "resting.unreadable.json").path))
}
