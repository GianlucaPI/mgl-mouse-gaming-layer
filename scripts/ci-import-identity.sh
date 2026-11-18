#!/bin/sh
# CI only: imports the signing identity from GitHub secrets into a temporary keychain,
# so release builds are signed with a stable identity (Accessibility survives updates).
#
# Env: MGL_SIGNING_P12_BASE64  base64 of the exported .p12 (identity "MGL Local Code Signing")
#      MGL_SIGNING_P12_PASSWORD password chosen when exporting the .p12
# Prints the identity name on stdout when imported; prints nothing if the secrets are empty.
set -eu
[ -n "${MGL_SIGNING_P12_BASE64:-}" ] || { echo "No signing secret: release will be signed ad-hoc." >&2; exit 0; }

KC="$RUNNER_TEMP/mgl-signing.keychain-db"
KC_PASS="$(openssl rand -hex 16)"
P12="$RUNNER_TEMP/mgl-signing.p12"
echo "$MGL_SIGNING_P12_BASE64" | base64 --decode > "$P12"

security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$P12" -k "$KC" -P "${MGL_SIGNING_P12_PASSWORD:-}" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KC" >/dev/null
# Put the temporary keychain in the search list so codesign finds the identity by name.
# shellcheck disable=SC2046
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
rm -f "$P12"
echo "MGL Local Code Signing"
