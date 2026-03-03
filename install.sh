#!/bin/bash
set -e

REPO="product-noob/whispr-app"
DMG_NAME="Whispr.dmg"
APP_NAME="WhisprFlow.app"
INSTALL_DIR="/Applications"
TMP_DIR=$(mktemp -d)
DMG_PATH="$TMP_DIR/$DMG_NAME"

echo "Downloading Whispr..."
curl -L "https://github.com/$REPO/releases/latest/download/$DMG_NAME" \
  -o "$DMG_PATH" --progress-bar

echo "Mounting disk image..."
VOLUME=$(hdiutil attach "$DMG_PATH" -nobrowse -quiet | tail -1 | awk '{print $NF}')

echo "Installing to $INSTALL_DIR..."
cp -R "$VOLUME/$APP_NAME" "$INSTALL_DIR/"

echo "Ejecting..."
hdiutil detach "$VOLUME" -quiet
rm -rf "$TMP_DIR"

echo "Done! Whispr installed to /Applications."
