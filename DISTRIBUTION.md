# WhisprFlow Distribution Guide

This guide explains how to build and distribute WhisprFlow as a DMG file.

## Prerequisites

- macOS with Xcode installed
- The WhisprFlow project

## Building for Distribution

### Step 1: Build Release Version

```bash
cd /Users/prince.jain/Documents/WisprFlow

# Clean and build Release configuration
xcodebuild -project WhisprFlow.xcodeproj \
  -scheme WhisprFlow \
  -configuration Release \
  clean build \
  CONFIGURATION_BUILD_DIR="./build/Release"
```

### Step 2: Create Distribution Folder

```bash
# Create a folder for the DMG contents
mkdir -p ./dist/WhisprFlow

# Copy the app to the distribution folder
cp -R ./build/Release/WhisprFlow.app ./dist/WhisprFlow/

# Create a symbolic link to Applications folder (for drag-to-install)
ln -s /Applications ./dist/WhisprFlow/Applications
```

### Step 3: Create the DMG

```bash
# Create the DMG file
hdiutil create -volname "WhisprFlow" \
  -srcfolder ./dist/WhisprFlow \
  -ov -format UDZO \
  ./dist/WhisprFlow.dmg
```

### Step 4: Clean Up (Optional)

```bash
# Remove the temporary distribution folder
rm -rf ./dist/WhisprFlow
rm -rf ./build
```

## One-Command Build

Run this single command to build and create the DMG:

```bash
cd /Users/prince.jain/Documents/WisprFlow && \
xcodebuild -project WhisprFlow.xcodeproj -scheme WhisprFlow -configuration Release clean build CONFIGURATION_BUILD_DIR="./build/Release" && \
mkdir -p ./dist/WhisprFlow && \
cp -R ./build/Release/WhisprFlow.app ./dist/WhisprFlow/ && \
ln -s /Applications ./dist/WhisprFlow/Applications && \
hdiutil create -volname "WhisprFlow" -srcfolder ./dist/WhisprFlow -ov -format UDZO ./dist/WhisprFlow.dmg && \
rm -rf ./dist/WhisprFlow ./build && \
echo "DMG created at: ./dist/WhisprFlow.dmg"
```

## Installation Instructions (for users)

1. Download `WhisprFlow.dmg`
2. Double-click to open the DMG
3. Drag `WhisprFlow.app` to the `Applications` folder
4. Eject the DMG
5. Open WhisprFlow from Applications
6. Grant necessary permissions:
   - **Microphone**: Required for recording
   - **Accessibility**: Required for global hotkeys

## Notes

- The app is not code-signed for distribution outside the App Store
- Users may need to right-click → Open the first time (Gatekeeper)
- For proper distribution, consider signing with a Developer ID certificate
