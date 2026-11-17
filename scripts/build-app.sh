#!/bin/sh
# Builds build/MGL.app (menu-bar app) and signs it.
#
#   ./scripts/build-app.sh            build + sign
#   ./scripts/build-app.sh --install  also copy to /Applications (or ~/Applications) and relaunch
#
# Signing identity, in order: $MGL_SIGN_IDENTITY, "MGL Local Code Signing" (see
# scripts/create-signing-identity.sh), otherwise ad-hoc. With ad-hoc signing macOS
# forgets the Accessibility permission after every rebuild.
set -eu
cd "$(dirname "$0")/.."

INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

APP_NAME="MGL"
BUNDLE_ID="local.mgl.MouseGamingLayer"
FULL_VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/MGLCore/MGL.swift)"
SHORT_VERSION="${FULL_VERSION%%-*}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="build/$APP_NAME.app"

echo "==> Building MGLMenuBar (release)"
swift build -c release --product MGLMenuBar 2>&1 | grep -v "search path" || true
BIN="$(swift build -c release --show-bin-path)/MGLMenuBar"
[ -x "$BIN" ] || { echo "Build failed: $BIN not found" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>          <string>MGL — Mouse Gaming Layer</string>
  <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>           <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>CFBundleShortVersionString</key>   <string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key>              <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>       <string>13.0</string>
  <key>LSUIElement</key>                  <true/>
  <key>NSHighResolutionCapable</key>      <true/>
  <key>NSHumanReadableCopyright</key>     <string>MGL $FULL_VERSION</string>
</dict>
</plist>
EOF
plutil -lint -s "$APP/Contents/Info.plist"

IDENTITY="${MGL_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-certificate -c "MGL Local Code Signing" >/dev/null 2>&1; then
  IDENTITY="MGL Local Code Signing"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "==> Signing ad-hoc (WARNING: Accessibility must be re-granted after every rebuild;"
  echo "    run ./scripts/create-signing-identity.sh once to avoid this)"
else
  echo "==> Signing with \"$IDENTITY\""
fi
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "    $(codesign -dr - "$APP" 2>&1 | grep designated)"

echo "==> Built $APP ($SHORT_VERSION build $BUILD_NUMBER)"

if [ "$INSTALL" = 1 ]; then
  DEST="/Applications"
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Quitting running $APP_NAME"
    pkill -x "$APP_NAME" || true
    sleep 1
  fi
  echo "==> Installing to $DEST/$APP_NAME.app"
  rm -rf "$DEST/$APP_NAME.app"
  ditto "$APP" "$DEST/$APP_NAME.app"
  open "$DEST/$APP_NAME.app"
fi
