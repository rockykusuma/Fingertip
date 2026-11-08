#!/bin/bash
# Builds a signed, notarized dist/Fingertip-<version>.dmg for a GitHub release:
# the universal app plus an Applications shortcut to drag it onto.
#
# Needs .env.local (copy .env.local.example): DEV_ID, the Developer ID
# Application identity, and NOTARY_PROFILE, a notarytool keychain profile.
# The copy in the DMG is signed with Developer ID and the hardened runtime,
# the DMG is notarized and stapled, and Gatekeeper checks it before we finish.
# Your own dist/Fingertip.app keeps its development signature, so its
# Accessibility grant survives.
set -euo pipefail
cd "$(dirname "$0")"

if [ -f .env.local ]; then set -a; . ./.env.local; set +a; fi
: "${DEV_ID:?Set DEV_ID in .env.local (see .env.local.example)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE in .env.local (see .env.local.example)}"
security find-identity -v -p codesigning | grep -qF "$DEV_ID" \
  || { echo "✗ \"$DEV_ID\" is not in your keychain (security find-identity -v -p codesigning)"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="dist/Fingertip-$VERSION.dmg"

UNIVERSAL=1 ./build.sh release

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/Fingertip.app "$STAGE/"

echo "→ Signing with Developer ID and the hardened runtime…"
codesign --force --options runtime --timestamp --sign "$DEV_ID" --identifier in.rockykusuma.fingertip "$STAGE/Fingertip.app"
codesign --verify --strict --verbose=2 "$STAGE/Fingertip.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Fingertip $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
codesign --force --timestamp --sign "$DEV_ID" "$DMG"

echo "→ Notarizing (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"

echo "✓ Built $DMG"
echo "SHA-256 (for the Homebrew cask):"
shasum -a 256 "$DMG"
