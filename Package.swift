// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rooms",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: rooms, matching, storage. No AppKit, fully testable.
        .target(name: "RoomsCore"),
        // The menu bar app.
        .executableTarget(
            name: "Rooms",
            dependencies: ["RoomsCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "RoomsCoreTests", dependencies: ["RoomsCore"]),
    ]
)
