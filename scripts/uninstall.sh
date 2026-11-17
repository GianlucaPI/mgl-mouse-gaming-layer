#!/bin/sh
# Uninstalls MGL from this Mac.
#
#   ./scripts/uninstall.sh            remove MGL.app (+ Launch at Login), stop running MGL / mgl
#   ./scripts/uninstall.sh --config   also delete ~/Library/Application Support/MGL (your config!)
#   ./scripts/uninstall.sh --prefs    also delete the app preferences (enabled, forced profile)
#   ./scripts/uninstall.sh --cert     also delete the "MGL Local Code Signing" identity
#   ./scripts/uninstall.sh --all      all of the above + reset MGL's Accessibility permission
#
#   --dry-run   only print what would be done      --yes   do not ask for confirmation
#
# The repository and its build/ folder are never touched.
set -eu

APP_NAME="MGL"
BUNDLE_ID="local.mgl.MouseGamingLayer"
CERT_NAME="MGL Local Code Signing"
CONFIG_DIR="$HOME/Library/Application Support/MGL"

DO_CONFIG=0; DO_PREFS=0; DO_CERT=0; DO_TCC=0; DRY=0; YES=0
for arg in "$@"; do
  case "$arg" in
    --config) DO_CONFIG=1 ;;
    --prefs) DO_PREFS=1 ;;
    --cert) DO_CERT=1 ;;
    --all) DO_CONFIG=1; DO_PREFS=1; DO_CERT=1; DO_TCC=1 ;;
    --dry-run) DRY=1 ;;
    --yes|-y) YES=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

run() {
  if [ "$DRY" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi
}

APPS=""
for dir in /Applications "$HOME/Applications"; do
  [ -d "$dir/$APP_NAME.app" ] && APPS="$APPS $dir/$APP_NAME.app"
done
HAS_CERT=0
security find-certificate -c "$CERT_NAME" >/dev/null 2>&1 && HAS_CERT=1

echo "MGL uninstall plan:"
if [ -n "$APPS" ]; then
  for app in $APPS; do echo "  - unregister Launch at Login, delete $app"; done
else
  echo "  - MGL.app not found in /Applications or ~/Applications"
fi
echo "  - stop running MGL app and CLI mgl processes (if any)"
[ "$DO_CONFIG" = 1 ] && echo "  - delete $CONFIG_DIR (config and backups)"
[ "$DO_PREFS" = 1 ] && echo "  - delete preferences ($BUNDLE_ID)"
if [ "$DO_CERT" = 1 ]; then
  if [ "$HAS_CERT" = 1 ]; then echo "  - delete keychain identity \"$CERT_NAME\""
  else echo "  - keychain identity \"$CERT_NAME\" not found (nothing to delete)"; fi
fi
[ "$DO_TCC" = 1 ] && echo "  - reset MGL's Accessibility permission (tccutil)"

if [ "$DRY" = 0 ] && [ "$YES" = 0 ]; then
  printf "Proceed? [y/N] "
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 1 ;; esac
fi

for app in $APPS; do
  if [ -x "$app/Contents/MacOS/$APP_NAME" ]; then
    run "$app/Contents/MacOS/$APP_NAME" --unregister-login-item || true
  fi
done
run pkill -x "$APP_NAME" || true
run pkill -x mgl || true
for app in $APPS; do run rm -rf "$app"; done

[ "$DO_CONFIG" = 1 ] && { run rm -rf "$CONFIG_DIR"; }
[ "$DO_PREFS" = 1 ] && { run defaults delete "$BUNDLE_ID" 2>/dev/null || true; }
if [ "$DO_CERT" = 1 ] && [ "$HAS_CERT" = 1 ]; then
  run security delete-identity -c "$CERT_NAME" || true
fi
[ "$DO_TCC" = 1 ] && { run tccutil reset Accessibility "$BUNDLE_ID" || true; }

echo "Done.$([ "$DRY" = 1 ] && echo ' (dry run: nothing was changed)')"
