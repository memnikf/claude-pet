#!/bin/zsh
set -e
cd "${0:A:h}"
APP="Питомец.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

/usr/bin/xcrun swiftc -parse-as-library -O -o "$APP/Contents/MacOS/ClaudePet" Sources/*.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Питомец</string>
	<key>CFBundleDisplayName</key><string>Питомец</string>
	<key>CFBundleExecutable</key><string>ClaudePet</string>
	<key>CFBundleIdentifier</key><string>dev.claudepet.app</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "собрано: $APP"
