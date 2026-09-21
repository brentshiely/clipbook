# Clipbook

A macOS clipboard history. Press **⇧⌘V** to open a 10 × 10 tile grid of everything you've copied, newest at the top left.

| Key | Action |
|---|---|
| ← / → | Move within the row (wraps to the previous/next row at the edges) |
| ↑ / ↓ | Move one full row |
| ↩ | Paste the selected tile into the app you were using |
| ⌘⌫ | Clear the whole Clipbook (asks to confirm) |
| esc | Close |

Scrolling past row 10 loads older history — there's no 100-item cap and no retention limit until you clear it.

Text, images and files are captured. Items marked concealed by password managers are skipped. Consecutive duplicates collapse. History lives in `~/Library/Application Support/Clipbook/history.sqlite` and never leaves your Mac.

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
