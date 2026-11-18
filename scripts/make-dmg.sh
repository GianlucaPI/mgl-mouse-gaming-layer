#!/bin/sh
# Packages build/MGL.app into build/MGL-<version>.dmg (drag-to-Applications layout).
#
#   ./scripts/build-app.sh --universal && ./scripts/make-dmg.sh
#
# The DMG contains MGL.app, a link to /Applications and a short first-launch guide.
# The app is NOT notarized: see "Install" in README.md for the first-launch steps.
set -eu
cd "$(dirname "$0")/.."

APP="build/MGL.app"
[ -d "$APP" ] || { echo "$APP not found: run ./scripts/build-app.sh first" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/MGL-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging"
ditto "$APP" "$STAGE/MGL.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/First launch - READ ME.txt" <<TXT
MGL $VERSION — Mouse Gaming Layer

1. Drag MGL.app onto the Applications folder.
2. Open MGL from Applications.
   MGL is not notarized by Apple, so the first time macOS blocks it:
     System Settings > Privacy & Security > scroll down > "Open Anyway" next to MGL,
     then confirm. (Alternatively, in Terminal:
       xattr -dr com.apple.quarantine /Applications/MGL.app )
3. Grant Accessibility when asked:
     System Settings > Privacy & Security > Accessibility > enable MGL.
   MGL starts by itself as soon as the permission is granted.
4. A mouse icon appears in the menu bar. Use "Edit Config..." to choose
   when MGL is active (by default: always; the example config limits it to
   World of Warcraft).

Documentation, known issues and source code: see the project page on GitHub.
TXT

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "MGL $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "==> Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
