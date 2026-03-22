#!/bin/bash
set -e

APP_SOURCE="$(cd "$(dirname "$0")" && pwd)/Whispr.app"
DEST="/Applications/Whispr.app"

echo "Installing Whispr..."

# Copy app to /Applications (overwrite if already present)
cp -R "$APP_SOURCE" "$DEST"

# Remove the quarantine extended attribute that triggers Gatekeeper.
# This is safe: Whispr is open-source at https://github.com/product-noob/whispr-app
xattr -cr "$DEST"

echo ""
echo "Done! Whispr has been installed to /Applications."
echo "You can now launch it from Spotlight or your Applications folder."
