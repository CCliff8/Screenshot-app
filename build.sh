#!/bin/zsh
# Builds Snip.app next to this script.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=Snip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/Snip "$APP/Contents/MacOS/Snip"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.snipapp.snip</string>
  <key>CFBundleName</key><string>Snip</string>
  <key>CFBundleExecutable</key><string>Snip</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
IDENTITY="Snip Local Signing"
security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || IDENTITY="-"
codesign --force --options runtime --sign "$IDENTITY" "$APP" 2>/dev/null || { echo "Signing with \"$IDENTITY\" failed, using ad-hoc"; codesign --force --options runtime --sign - "$APP"; }
echo "Built $APP"
