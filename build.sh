#!/bin/bash
# Builds dist/AudioSplitter.app
set -euo pipefail
cd "$(dirname "$0")"

# The Xcode target already compiles AppIcon.icon with actool (Liquid Glass on macOS 26
# plus AppIcon.icns for older systems), writes Info.plist and signs ad-hoc.
xcodebuild -project AudioSplitter.xcodeproj -scheme AudioSplitter -configuration Release \
  -derivedDataPath .build -quiet build

APP="dist/AudioSplitter.app"
rm -rf "$APP"
mkdir -p dist
cp -R ".build/Build/Products/Release/AudioSplitter.app" "$APP"

# Make Finder and the Dock pick up the new icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Built $APP"
