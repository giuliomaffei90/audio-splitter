#!/usr/bin/env bash
# Personal dev helper: build a Release macOS build of Audio Splitter, drop it
# in ~/Downloads, kill any running instance, and relaunch the fresh build.
set -euo pipefail

APP_NAME="AudioSplitter"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$PROJECT_DIR/build/Build/Products/Release/$APP_NAME.app"
DEST_APP="$HOME/Downloads/$APP_NAME.app"

echo "==> Closing running instances of $APP_NAME..."
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "==> Building Release macOS app..."
cd "$PROJECT_DIR"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath build -quiet build

echo "==> Copying build to $DEST_APP..."
rm -rf "$DEST_APP"
cp -R "$BUILT_APP" "$DEST_APP"

echo "==> Launching $DEST_APP..."
open "$DEST_APP"

echo "Done."
