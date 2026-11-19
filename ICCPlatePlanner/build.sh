#!/bin/bash
# Builds "ICC Plate Planner.app" (universal: Apple silicon + Intel). Needs only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"
APP="ICC Plate Planner.app"
rm -rf build "$APP"
mkdir -p build

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos13.0" Sources/*.swift -o "build/planner-$arch"
done
lipo -create build/planner-arm64 build/planner-x86_64 -o build/planner

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/planner "$APP/Contents/MacOS/ICC Plate Planner"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/DeptLogo.png "$APP/Contents/Resources/DeptLogo.png"

build/planner --make-icon build/icon.png
mkdir -p build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"
