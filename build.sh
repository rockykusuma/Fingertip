#!/bin/bash
# Builds dist/Fingertip.app from the SwiftPM executable.
#
#   ./build.sh            release build for this Mac's architecture
#   ./build.sh debug      debug build
#   UNIVERSAL=1 ./build.sh   Apple Silicon + Intel (release.sh uses this)
#   CODESIGN_IDENTITY="Fingertip Dev" ./build.sh
#
# Accessibility permission is tied to the code signature. With ad-hoc
# signing ("-") macOS treats every rebuild as a new app and you have to
# re-grant it. So by default this uses the first "Apple Development"
# identity in your keychain (free with an Apple ID in Xcode). No such
# identity → ad-hoc. Override with CODESIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Fingertip"
APP="dist/$APP_NAME.app"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
IDENTITY="${IDENTITY:--}"

ARCHS=""
if [ "${UNIVERSAL:-0}" = 1 ]; then ARCHS="--arch arm64 --arch x86_64"; fi
swift build -c "$CONFIG" $ARCHS
BIN="$(swift build -c "$CONFIG" $ARCHS --show-bin-path)/$APP_NAME"

pkill -x "$APP_NAME" 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign "$IDENTITY" --identifier in.rockykusuma.fingertip "$APP"

echo "Built $APP ($CONFIG, signed with: $IDENTITY)"
echo "Run:   open $APP"
