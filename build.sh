#!/bin/zsh
# Builds Question.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/Question.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Question "$APP/Contents/MacOS/Question"
# SwiftPM resource bundles (Textual's syntax highlighter) live in Contents/Resources.
mkdir -p "$APP/Contents/Resources"
for bundle in .build/release/*.bundle(N); do cp -R "$bundle" "$APP/Contents/Resources/"; done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Question</string>
  <key>CFBundleIdentifier</key><string>com.openblau.question</string>
  <key>CFBundleExecutable</key><string>Question</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"

# Install to /Applications so the login item points at a stable location.
pkill -x Question 2>/dev/null || true
rm -rf /Applications/Question.app
cp -R "$APP" /Applications/Question.app
echo "Installed /Applications/Question.app"
[[ "${1:-}" == "--no-launch" ]] || open /Applications/Question.app
