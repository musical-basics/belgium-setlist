#!/bin/bash
# Build ShowRunner and wrap the release binary into a double-clickable ShowRunner.app
# placed next to showrunner.json (one level above this package).
set -euo pipefail

cd "$(dirname "$0")"
PKG_DIR="$(pwd)"
SHOW_ROOT="$(cd .. && pwd)"
APP="$SHOW_ROOT/ShowRunner.app"

echo "==> swift build -c release"
swift build -c release

BIN="$PKG_DIR/.build/release/ShowRunner"
if [[ ! -x "$BIN" ]]; then
  echo "ERROR: build produced no binary at $BIN" >&2
  exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ShowRunner"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>            <string>ShowRunner</string>
    <key>CFBundleIdentifier</key>            <string>com.lionelyu.showrunner</string>
    <key>CFBundleName</key>                  <string>ShowRunner</string>
    <key>CFBundleDisplayName</key>           <string>ShowRunner</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>LSMinimumSystemVersion</key>        <string>13.0</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>LSUIElement</key>                   <false/>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so macOS Gatekeeper/CoreAudio are happy launching it locally.
# Distinguish "codesign absent" (fine) from "codesign present but failed" (must surface).
if command -v codesign >/dev/null 2>&1; then
  if codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && codesign -v "$APP" >/dev/null 2>&1; then
    echo "    ✓ Signed ad-hoc"
  else
    echo "    ⚠ WARNING: ad-hoc codesign failed — check system security policy." >&2
    echo "      The app may be blocked by Gatekeeper on some machines." >&2
  fi
fi

echo "==> Done."
echo "    App:  $APP"
echo "    Run:  open \"$APP\"    (or double-click it in Finder)"
echo "    The app reads:  $SHOW_ROOT/showrunner.json"
