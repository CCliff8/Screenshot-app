# Snip

A fast, Snipping Tool–style screenshot and screen-recording app for macOS.

Press a shortcut, drag over the area you want, and it's saved and copied to your clipboard.
Open the app any time to browse your captures, mark them up with a pen or highlighter, or replay recordings.

## Features

- **Screenshot** – global shortcut (default **⌃⇧S**), drag to select an area, auto-saved and copied to the clipboard
- **Screen recording** – global shortcut (default **⌃⇧R**), record a selected area (or the full screen with **Return**) to `.mp4`; click the red menu-bar icon or press the shortcut again to stop
- **Editor** – pen, highlighter, eraser, colors, width, undo/redo, copy, save, delete
- **Gallery** – every screenshot and recording in one place
- **Customizable shortcuts** – change them in Settings (**⌘,**) with a click-and-press recorder

Captures are saved to `~/Pictures/Screenshots/`.

## Requirements

- **macOS 15 (Sequoia) or later**
- **Xcode or the Xcode Command Line Tools** with Swift 5.9+ (`xcode-select --install`) to build from source
- **Screen Recording permission** (see below)

## Install

```sh
git clone https://github.com/<your-username>/snip.git
cd snip
./install.sh
```

This builds the app and copies it to `/Applications`. To just build it in the project folder, run `./build.sh` and then `open Snip.app`.

## Permissions

The first capture asks for **Screen Recording** access. Allow it in
**System Settings → Privacy & Security → Screen & System Audio Recording**, then **quit and reopen Snip**.

Because the app is built locally with an ad-hoc signature, macOS treats each rebuild as a new app. After rebuilding or updating, you may need to remove Snip from that list, add it again, and restart the app.
To avoid this, create a stable local signing identity once with `scripts/make_cert.sh`; `build.sh` will use it automatically.

## Usage

| Action | How |
| --- | --- |
| Take a screenshot | **⌃⇧S**, then drag. **Esc** cancels |
| Record the screen | **⌃⇧R**, then drag (or **Return** for full screen). Press **⌃⇧R** again to stop |
| Open gallery / editor | Click the Dock or menu-bar icon |
| Change shortcuts | **⌘,** (Settings) |

## Project layout

```
Sources/Snip/   Swift sources (AppKit + SwiftUI + ScreenCaptureKit)
Resources/      App icon
scripts/        Icon generator and optional local signing helper
build.sh        Builds Snip.app
install.sh      Builds and installs to /Applications
```

## License

[MIT](LICENSE)
