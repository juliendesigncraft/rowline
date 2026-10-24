#!/bin/zsh
# Builds Rowline.app into ./build. Needs only the Xcode Command Line Tools.
# Optional: SIGN_IDENTITY="Your Certificate Name" ./build.sh
# Without it the app is signed ad-hoc, and macOS asks for the Accessibility permission again after every rebuild.
set -e
cd "$(dirname "$0")"
APP="build/Rowline.app"
pkill -x Rowline 2>/dev/null && sleep 0.5 || true      # quitting puts parked windows back in view
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
[ -f assets/AppIcon.icns ] && cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
swiftc -O main.swift motore.swift tasti.swift pannello.swift barra.swift extra.swift -o "$APP/Contents/MacOS/Rowline"
if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --identifier com.juliendesigncraft.rowline "$APP"
else
    echo "No SIGN_IDENTITY set: signing ad-hoc."
    codesign --force --sign - --identifier com.juliendesigncraft.rowline "$APP"
fi
echo "Built: $APP"
