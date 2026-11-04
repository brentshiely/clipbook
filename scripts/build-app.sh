#!/bin/zsh
# Builds a release Clipbook.app into build/ (menu-bar only). Signed with your Apple Development
# certificate if you have one, so the Accessibility permission survives rebuilds; ad-hoc otherwise.
# Usage: scripts/build-app.sh [--install]   # --install copies to ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Clipbook"

APP="build/Clipbook.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Clipbook"

# App icon: drawn by the app itself, then packed into an .icns.
mkdir -p "$APP/Contents/Resources" build/AppIcon.iconset
"$BIN" --icon build/icon-1024.png
for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.clipbook</string>
    <key>CFBundleName</key><string>Clipbook</string>
    <key>CFBundleExecutable</key><string>Clipbook</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# macOS ties the Accessibility grant to the signature. Ad-hoc signatures change on every build,
# which makes macOS ask again; a real certificate keeps the grant across rebuilds.
IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development/ { print $2; exit }')"
codesign --force --sign "${IDENTITY:--}" --identifier local.clipbook "$APP"
[[ -n "$IDENTITY" ]] || echo "No Apple Development certificate found; signed ad-hoc (Accessibility must be re-approved after each rebuild)."
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Clipbook.app
    cp -R "$APP" ~/Applications/Clipbook.app
    echo "Installed ~/Applications/Clipbook.app"
fi
