#!/bin/bash
# Builds dist/Fingertip.app from the SwiftPM executable.
#
#   ./build.sh            release build, ad-hoc signed
#   ./build.sh debug      debug build
#   CODESIGN_IDENTITY="Fingertip Dev" ./build.sh
#
# Accessibility permission is tied to the code signature. With ad-hoc
# signing ("-") macOS treats every rebuild as a new app and you have to
# re-grant it. To avoid that, create a self-signed "Code Signing"
# certificate in Keychain Access (Certificate Assistant → Create a
# Certificate… → type "Code Signing") and pass its name as CODESIGN_IDENTITY.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Fingertip"
APP="dist/$APP_NAME.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

swift build -c "$CONFIG"

pkill -x "$APP_NAME" 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

codesign --force --deep --sign "$IDENTITY" --identifier in.rockykusuma.fingertip "$APP"

echo "Built $APP ($CONFIG, signed with: $IDENTITY)"
echo "Run:   open $APP"
