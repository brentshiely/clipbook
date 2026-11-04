# Clipbook

A macOS clipboard history. Press **⇧⌘V** to open a grid of everything you've copied — 8 columns × 3 rows of large tiles, newest at the top left. Short text is blown up to fill its tile ("Cat" shouts), images are shown whole, never cropped, and copied video files show a frame from the video with a play button (the frame is saved, so it survives moving or deleting the file). When there are more than 24 items, a footer shows where you are and how many items sit below.

| Key | Action |
|---|---|
| ← / → | Move within the row (wraps to the previous/next row at the edges) |
| ↑ / ↓ | Move one full row |
| ↩ or double-click | Paste the selected tile into the app you were using |
| ⌘S | Image: save it as a PNG file in `~/Pictures/Clipbook` and show it in Finder. Video: show the original file in Finder |
| hover | A tooltip lists the commands available for that tile |
| click | Select a tile (the scroll wheel scrolls the grid) |
| space | Play the selected video inside Clipbook (space pauses, ←/→ seek 5 s, esc returns to the grid) |
| ⌫ | Delete the selected tile permanently |
| ⌘⌫ | Clear the whole Clipbook (asks to confirm) |
| esc | Close |

Scrolling past row 3 loads older history — there's no 100-item cap and no retention limit until you clear it.

Text, images and files are captured. Copies from password managers are never saved: items flagged as concealed are skipped, and so is anything copied while a known password-manager app (1Password, Bitwarden, Apple Passwords, KeePassXC and others) is in front. ⌫ deletes the selected tile permanently (its bytes are overwritten in the database file), and ⌘⌫ clears everything. Consecutive duplicates collapse. History lives in `~/Library/Application Support/Clipbook/history.sqlite` and never leaves your Mac.

## Build & install

```sh
scripts/build-app.sh --install     # builds build/Clipbook.app, copies to ~/Applications
open ~/Applications/Clipbook.app
```

**One-time permission:** to paste with ↩, Clipbook synthesizes ⌘V, which needs
System Settings → Privacy & Security → Accessibility → enable Clipbook.
Without it, ↩ still puts the item on your clipboard (paste manually with ⌘V).
The hotkey and grid need no permission. If you rebuild and paste stops working, toggle Clipbook off/on in that list.

Clipbook launches at login (enabled on first run; untick **Launch at Login** in its menu-bar menu to turn it off).

⇧⌘V is "Paste and Match Style" in many apps; Clipbook takes it over globally.

## Development

```sh
swift test                                   # store, dedupe, paging, grid navigation, watcher
.build/debug/Clipbook --snapshot out.png     # render the grid over sample data
```

Layout: `Sources/ClipbookCore` (SQLite store, pasteboard watcher, grid navigation — no UI), `Sources/Clipbook` (menu bar, hotkey, panel, SwiftUI grid).

## Adding a command

Add the key handling in `ClipbookViewModel.handleKey`, then list it in `Sources/ClipbookCore/TileActions.swift` so the hover tooltip shows it.
