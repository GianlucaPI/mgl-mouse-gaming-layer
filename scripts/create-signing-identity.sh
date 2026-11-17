#!/bin/sh
# Creates a local, self-signed code-signing identity "MGL Local Code Signing" in your
# login keychain (run once). Signing MGL.app with a stable identity lets macOS remember
# the Accessibility permission across rebuilds; ad-hoc signatures change on every build.
#
# The certificate is only used on this Mac to sign MGL; it is not trusted by anyone else.
# Remove it any time with Keychain Access (search "MGL Local Code Signing").
#
# Env: KEYCHAIN=<path> to use another keychain (default: login keychain).
set -eu

NAME="MGL Local Code Signing"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists in $KEYCHAIN — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P12_PASS="$(openssl rand -hex 16)"

cat > "$TMP/cert.cfg" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage         = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cfg" 2>/dev/null

# LibreSSL (macOS default) writes a PKCS#12 that `security` can import; OpenSSL 3 needs -legacy.
LEGACY=""
if openssl version | grep -q "^OpenSSL 3"; then LEGACY="-legacy"; fi
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$P12_PASS"

# -T: let codesign use the private key without a confirmation dialog.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\" in $KEYCHAIN."
echo "Now build the app with: ./scripts/build-app.sh"
echo "(If macOS asks whether codesign may use the key, choose \"Always Allow\".)"
