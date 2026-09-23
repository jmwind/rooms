# Contributing

Use Xcode 16 or later (or its Command Line Tools) and run `make test` before
submitting changes. Keep changes focused, and include reproduction steps and how
you checked the change.

## How it's put together

- `Sources/RoomsCore` is the pure logic, with no AppKit: layouts (`Layout.swift`,
  `GridLayout.swift`), recognising an arrangement (`Arrangement.swift`), matching
  saved windows to open ones (`WindowSlot.swift`), room search (`Matcher.swift`)
  and `rooms.json` (`RoomStore.swift`). Everything here should be covered by tests
  in `Tests/RoomsCoreTests`.
- `Sources/Rooms` is the menu-bar app: `Windows/WindowEngine.swift` finds, moves,
  parks and measures windows through the Accessibility API; `Palette/`, `Picker/`
  and `Overlay/` are the ⌥Space panel, the window picker, and the toast, preview
  and welcome panels.

## Things to keep true

- **Nothing is ever closed or lost.** A window's way back is written to
  `resting.json` before it's parked, and only cleared once the window is confirmed
  back. Show Everything, quitting and relaunching after a crash all restore.
- **Window work runs one at a time** (`inTurn` in `AppDelegate`): switching,
  saving, laying out after a display change and Show Everything must not overlap.
- **A layout never pushes windows off screen or on top of each other**, except
  Stack, which overlaps on purpose. Stored layouts are re-checked where they're
  applied and fall back to Auto.
- **No network access**, no analytics, nothing leaves the Mac.
- Glass (macOS 26) is looked up at run time (`Overlay/Glass.swift`) so the app
  still builds with the macOS 15 SDK.

## Testing on a real desk

The app moves real windows, so unit tests don't cover everything. Before trying
something risky, save your desk and put it back afterwards:

```sh
swiftc -O Tools/desksnap.swift -o Tools/desksnap
Tools/desksnap save /tmp/desk.json
Tools/desksnap restore /tmp/desk.json
```

Check a change on a laptop screen and on an external monitor if you can, with a
few apps that have large minimum sizes (Figma, WhatsApp, Outlook). Include your
macOS version and display arrangement when reporting a problem, and leave out
window titles, `rooms.json`, `resting.json` and logs, which can contain private
information.

## Before publishing a release

1. Update `CFBundleShortVersionString` in `Support/Info.plist`.
2. Run `make test`, then `make release`: it builds one binary for Apple silicon and
   Intel, ad-hoc signs it (it isn't notarized) and prints the ZIP's SHA-256.
3. Attach `build/Rooms-<version>.zip` to a GitHub release, and update the version
   and SHA-256 in the Homebrew cask (`saragordic/homebrew-tap`).

Don't upload logs, `rooms.json`, screen recordings with real windows, build
products or signing certificates.
