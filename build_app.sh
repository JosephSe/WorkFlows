#!/bin/bash
# Builds build/WorkFlows.app from the Swift package.
#   ./build_app.sh             build only
#   ./build_app.sh --install   build, copy to /Applications, launch
set -euo pipefail
cd "$(dirname "$0")"

APP="build/WorkFlows.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/WorkFlows"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WorkFlows"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>WorkFlows</string>
    <key>CFBundleDisplayName</key><string>WorkFlows</string>
    <key>CFBundleIdentifier</key><string>local.workflows.app</string>
    <key>CFBundleExecutable</key><string>WorkFlows</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>WorkFlows</string>
            <key>CFBundleURLSchemes</key><array><string>workflows</string></array>
        </dict>
    </array>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>WorkFlows connects your Bluetooth speaker or headphones when a workflow runs.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>WorkFlows uses AppleScript to set the system volume.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for running locally and for Launch at Login.
codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x WorkFlows 2>/dev/null || true
    rm -rf /Applications/WorkFlows.app
    cp -R "$APP" /Applications/
    open /Applications/WorkFlows.app
    echo "Installed to /Applications and launched"
fi
