#!/bin/sh
# Runs the unit tests. With Command Line Tools only (no Xcode), SwiftPM does not
# find the swift-testing macro plugin on its own, so we point to it explicitly.
set -e
cd "$(dirname "$0")/.."
PLUGIN_DIR="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$PLUGIN_DIR" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
else
  exec swift test "$@"
fi
