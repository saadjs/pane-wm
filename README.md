# Pane

A small, native macOS menu bar app for switching apps and arranging windows with your own keyboard shortcuts.

- **App shortcuts:** one shortcut per app. It launches the app, brings it forward, restores it if minimized or hidden, and cycles through its windows when pressed again.
- **Window shortcuts:** halves, maximize, almost maximize, center, grow or shrink, and move to another display, with a configurable gap.
- **Native and light:** SwiftUI and AppKit only, no dependencies, no network access, no telemetry. Idle, it uses no CPU.

Requires macOS 14 Sonoma or later.

## Install

```sh
brew install --cask saadjs/tap/pane
```

## Set up

1. Open Pane. Its settings appear on first launch; later, click the Pane symbol in the menu bar and choose **Settings…**, or open Pane again.
2. Choose **Open Settings…** in the banner and turn on Pane under **Privacy & Security → Accessibility**. macOS requires this for any app that moves or focuses other apps' windows. Pane notices the change within a second; its menu bar symbol is a warning triangle while access is missing.
3. Under **Apps**, add an app, click **Record**, and press the shortcut you want. Escape cancels; the ⓧ button clears it.
4. Under **Windows**, choose **Use Default Shortcuts** or record your own.
5. Under **General**, adjust the gap, the almost-maximize inset, the resize step, and launch at login.

### Default window shortcuts

| Action | Shortcut | Behavior |
| --- | --- | --- |
| Left / right half | ⌃⌥← / ⌃⌥→ | Tile into that half, with the gap between halves and at screen edges. |
| Top / bottom half | ⌃⌥↑ / ⌃⌥↓ | Same, vertically. |
| Maximize | ⌃⌥↩ | Fill the desktop around the menu bar and Dock. Not full screen; no new Space. |
| Almost maximize | ⌃⌥⇧↩ | Fill the desktop with the configured inset on each side. |
| Center | ⌃⌥C | Center the window, keeping its size. |
| Make smaller / bigger | ⌃⌥- / ⌃⌥= | Change width and height by the resize step around the window's center. |
| Next / previous display | ⌃⌥⌘→ / ⌃⌥⌘← | Send the window to the display to the right or left, wrapping around. A tiled window stays tiled; any other keeps its size and relative place. |

Shortcuts start unassigned, and every one can be changed. A shortcut must include Control, Option, or Command.

### Good to know

- Actions apply to the focused window, on the screen that holds most of it.
- Fixed-size windows are moved into place without resizing. Apps can enforce minimum sizes; Pane keeps whatever size the app accepts.
- Full-screen windows are left alone.
- A warning appears next to a shortcut that macOS could not register, or that an enabled macOS shortcut (Mission Control, Spotlight, screenshots…) also uses.
- Shortcuts are stored as physical keys; their labels use the keyboard layout active when you recorded them.
- Settings live in `~/Library/Application Support/sh.saad.pane/settings.json`. A file Pane can't read is reported and left untouched.

## Build from source

Requirements: Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
scripts/run
```

This generates `Pane.xcodeproj`, builds the Debug configuration, and launches it. Debug builds are a separate app, **Pane Dev** (`sh.saad.pane.dev`), with their own Accessibility entry and settings, so they don't disturb an installed release. To work in Xcode instead, run `xcodegen generate` and open `Pane.xcodeproj`.

macOS ties the Accessibility grant to the app's code signature. Without a signing team, builds are signed to run locally and macOS asks for access again after every build. To keep the grant, set your Apple Developer Team ID:

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
```

`Config/Signing.local.xcconfig` is ignored by Git.

```sh
swift test
```

runs the unit tests for `PaneCore`, the Swift package holding configuration, persistence, and window geometry. The app itself is in `Sources/Pane`.

## Releasing

```sh
scripts/release              # build, sign, notarize, staple, zip
scripts/release --publish    # …then create the GitHub release and update the Homebrew cask
```

The version comes from `MARKETING_VERSION` in `project.yml`, or pass one as the first argument. The script archives the Release configuration, exports a Developer ID build, checks its identity and hardened runtime, notarizes and staples it, and writes `build/release/Pane-<version>.zip` with a matching `pane.rb` cask. `--publish` uploads the zip to a `v<version>` GitHub release and commits the cask to a local checkout of [saadjs/homebrew-tap](https://github.com/saadjs/homebrew-tap) (`~/src/homebrew-tap`, or `TAP_DIR`).

It requires a Developer ID Application certificate and a `notarytool` keychain profile named `pane-notary`:

```sh
xcrun notarytool store-credentials pane-notary \
  --key <AuthKey_XXXX.p8> --key-id <key-id> --issuer <issuer-id>
```

`scripts/release --skip-notarize` rehearses everything short of Apple's notary service.

## License

[MIT](LICENSE)
