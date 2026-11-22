# Screenshot Pro

A native macOS menu-bar screenshot tool: region, window and scrolling capture, annotations, mosaic, pin to screen, and OCR. Built with Swift, AppKit and ScreenCaptureKit. Requires macOS 14 or later. The UI is available in 10 languages.

Inspired by the workflow of Xnip. Not affiliated with Xnip.

## Install / update

You need macOS 14+ and the Command Line Tools (`xcode-select --install`). Xcode is not required.

```bash
git clone https://github.com/ShinChven/screenshot-pro.git
cd screenshot-pro
./scripts/setup-signing.sh   # optional, run once: creates a local code-signing certificate
./scripts/install.sh
```

`install.sh` builds the app, packages it, installs it to `/Applications/Screenshot Pro.app` and launches it.

On first use, turn on **Screenshot Pro** in System Settings → Privacy & Security → Screen & System Audio Recording, then choose "Relaunch" from the menu-bar icon.

> Running `./scripts/setup-signing.sh` before your first build is recommended. It creates a self-signed certificate for this Mac in your login keychain, and `build.sh` uses it automatically, so rebuilding does not revoke the Screen Recording permission.
> Without it, the app is ad-hoc signed and you have to grant the permission again after every rebuild. If captures show only the wallpaper, or the app keeps saying it has no permission, run
> `tccutil reset ScreenCapture com.local.screenshotpro`, then reopen the app and grant it again.

## Features

| Feature | How |
|---|---|
| Capture | `⇧⌘2` (configurable in Settings) |
| Scrolling capture | `⌥⌘2`, or the scroll button in the capture toolbar. Select an area, scroll the content yourself, then click "Done" |
| Text recognition (OCR) | `⇧⌘1`. Select an area and the text is recognized and copied. Supports Chinese, English and Japanese |
| Delayed capture | Menu bar → 3-second delayed capture |
| Region capture | Drag to select. Drag edges or corners to resize, drag inside to move, arrow keys to nudge (`⇧` for 10 pt) |
| Window capture | Windows highlight on hover; click to select |
| Standalone window capture | `⌥`-click. Captures the window even when covered, optionally with its shadow |
| Multi-window capture | `⌘`-click to select several windows, then `↩` to combine them into one image |
| Magnifier / color picker | Pixel magnifier and color value shown before selecting; `C` copies HEX, `⇧C` copies RGB |
| Mosaic | Rectangle by default: drag to move, drag handles to resize. Switch to brush mode in the style bar |
| Annotations | `R` rectangle · `O` ellipse · `A` arrow · `L` line · `P` pen · `H` highlighter · `T` text · `M` mosaic · `N` step number |
| Edit annotations | Click any annotation to drag it, with any tool active. Selected rectangles, ellipses and mosaics show 8 resize handles; arrows and lines have draggable endpoints. New annotations are selected automatically. `⌫` deletes; pick a color or width to change the selected one; double-click text to edit it; hold `⇧` for squares or 45° snapping |
| Step numbers | Each click places the next number. Deleting one renumbers the rest |
| Undo / redo | `⌘Z` / `⇧⌘Z` |
| Finish | `↩` or double-click inside the selection. Copies to the clipboard by default; Settings can switch it to save, or copy and save |
| Copy / save | `⌘C` / `⌘S` |
| Pin to screen | Pin button in the toolbar. Scroll to zoom, `1`–`9`/`0` set opacity, right-click for a menu, double-click or `Esc` to close |
| History | Menu bar → Recent captures. Click to pin, `⌥`-click to copy |
| Shutter sound | Plays the system screenshot sound on capture and pin; can be turned off in Settings |
| Cancel | `Esc`; right-click goes back to selecting |

## Languages

The app follows the system language: English, 简体中文, 繁體中文, 日本語, 한국어, Français, Deutsch, Español, Português (BR) and Русский. Other languages fall back to English.

- UI strings in the code use the Simplified Chinese text as the localization key, e.g. `L("...")` or `L("...%@", name)`. SwiftUI string literals are localized automatically.
- Translations live in `scripts/i18n.py`. `./scripts/build.sh` generates `Resources/Localization/*.lproj` from it.
- `python3 scripts/i18n.py --check` reports missing translations, string interpolation, and placeholder mismatches.
- To run in a specific language: `"build/Screenshot Pro.app/Contents/MacOS/ScreenshotPro" -AppleLanguages "(ja)"`

## Development

```bash
swift build                              # debug build
.build/debug/ScreenshotPro --selftest    # offline self-tests (scroll stitching, annotation rendering, drag interactions); no Screen Recording permission needed
./scripts/build.sh                       # package into build/Screenshot Pro.app
```

Source layout (`Sources/ScreenshotPro/`):

- `App/`: entry point, menu bar, global hotkeys (Carbon), permissions, settings
- `Capture/`: screen capture (ScreenCaptureKit), overlay windows, selection and window detection, magnifier, toolbar
- `Annotation/`: annotation model and rendering
- `Features/`: pin windows, scrolling capture (capture loop and stitching), OCR (Vision)
- `Output/`: copy and save, history

## License

[MIT](LICENSE)
