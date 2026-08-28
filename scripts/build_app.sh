#!/bin/sh
# Assembles a real .app bundle around the SPM-built executable.
#
# The plain `swift build`/`swift run` executable already works without
# this -- it gets NSBluetoothAlwaysUsageDescription via an Info.plist
# embedded straight into its Mach-O __info_plist section (see
# Package.swift). That trick is only needed because a bare binary has no
# bundle Info.plist to read; a real .app bundle uses Contents/Info.plist
# normally, which is what this script sets up, plus an ad-hoc code
# signature so macOS treats every rebuild as the same stable app identity
# (otherwise Gatekeeper/TCC would prompt for Bluetooth access again on
# every rebuild, since an unsigned binary's identity is its exact bytes).
set -e

cd "$(dirname "$0")/.."

APP_NAME="pi-bluetooth-configuration-client-mac"
CONFIG="release"
BUNDLE="$APP_NAME.app"

swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$BUNDLE/Contents/Info.plist"

codesign --force --deep --sign - "$BUNDLE"

echo "Built $BUNDLE"
