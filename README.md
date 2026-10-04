# QRBar

Create and read QR codes from the macOS menu bar. A native port of [Tray QR](https://github.com/Tray-Land/tray-qr) for Windows.

Click the menu bar icon to open a popover, type or paste some text, and the QR code appears. You can also point it at a QR code on screen or in an image to read what it says.

## Features

### Create
- The QR code updates as you type.
- Pick the code color and the background color, or reset to black on white. Low-contrast combinations get a warning.
- Choose the error-correction level (L, M, Q, H).
- Copy the image (⇧⌘C), save it as a PNG (⌘S), or drag it into Finder, a chat, or a document.

### Read
- Select part of the screen and read any codes in it (uses the system screenshot UI; needs Screen Recording permission).
- Paste an image (⌘V), open an image file (⌘O), or drop one onto the popover.
- Reads QR, Micro QR, Data Matrix, Aztec, PDF417, EAN-13, UPC-E, and Code 128.
- Open links, copy the decoded text, or turn a result into a new code.

### Menu bar app
- Menu bar icon only, with no Dock icon or main window. The icon is a template image, so it follows the menu bar's appearance.
- Right-click (or Control-click) the icon for **Open**, **Settings**, and **Quit**.
- Optionally launch at login.
- Works entirely offline. Nothing runs while the popover is closed.

## Requirements

- macOS 15 Sequoia or later
- To build: Xcode 26 or later

## Build and run

Open `QRBar.xcodeproj` and run the **QRBar** scheme, or:

```sh
xcodebuild -project QRBar.xcodeproj -scheme QRBar -configuration Release build
```

To distribute, set your team under **Signing & Capabilities** (the project signs ad hoc by default) and archive.

### Tests

The QR logic lives in the `QRBarKit` package with no UI dependency, so it tests on its own:

```sh
cd QRBarKit && swift test
```

They also run from Xcode (⌘U) through the QRBar scheme.

## Project layout

| Path | What's there |
| --- | --- |
| `QRBar/QRBarApp.swift` | Entry point and app delegate (agent app, Edit menu for text-field shortcuts, first-run popover) |
| `QRBar/StatusItemController.swift` | Menu bar icon, popover, and right-click menu |
| `QRBar/Models/` | `@Observable` state for the popover, the Create and Read tabs, and launch at login |
| `QRBar/Services/` | Screen capture, drag-and-drop and clipboard types |
| `QRBar/Views/` | SwiftUI views |
| `QRBarKit/` | Encoding (Core Image), rendering (Core Graphics), and decoding (Vision), with Swift Testing tests |

### Notes
- **Why `NSStatusItem` rather than `MenuBarExtra`?** `MenuBarExtra` can't be opened from code. The app needs that to bring the popover back after a screen capture or a save/open panel, and on first launch. It also can't show a separate right-click menu. The UI is still all SwiftUI, hosted in an `NSPopover`.
- **Sandboxing:** the app is sandboxed with the hardened runtime. Its only extra entitlement is read/write access to files the user picks.
- **Concurrency:** Swift 6 language mode, with MainActor default isolation and approachable concurrency in the app target. Image decoding and barcode detection run off the main actor in `QRBarKit`.

## License

MIT
