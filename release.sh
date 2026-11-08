#!/bin/bash
# Builds dist/Fingertip-<version>.dmg for a GitHub release: the app plus an
# Applications shortcut to drag it onto.
#
# The copy in the DMG is ad-hoc signed. Without a paid Developer ID and
# notarization macOS warns on first launch either way (see README, Install),
# and ad-hoc keeps your personal development certificate out of a public
# download. Your own dist/Fingertip.app keeps its normal signature.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="dist/Fingertip-$VERSION.dmg"

UNIVERSAL=1 ./build.sh release

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/Fingertip.app "$STAGE/"
codesign --force --deep --sign - --identifier in.rockykusuma.fingertip "$STAGE/Fingertip.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Fingertip $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
echo "Built $DMG"
