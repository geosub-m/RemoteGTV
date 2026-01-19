#!/bin/bash

# Configuration
APP_NAME="RemoteGTV"
BUILD_DIR="build"
ICONS_SOURCE="src/AppIcon.png"
ICON_SET="AppIcon.iconset"

# Cleanup
echo "Cleaning up previous build..."
rm -rf "$BUILD_DIR"
rm -rf "$APP_NAME.app"
rm -rf "$ICON_SET"
rm -f "AppIcon.icns"

# Create Directories
echo "Creating application structure..."
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Compile Swift Code
echo "Compiling Swift sources..."
swiftc -o "$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    src/RemoteTVApp.swift \
    src/ContentView.swift \
    src/NetworkManager.swift \
    src/RemoteProtocol.swift \
    src/ProtocolBuffer.swift \
    src/CertUtils.swift \
    src/Logger.swift

if [ $? -ne 0 ]; then
    echo "Error: Compilation failed!"
    exit 1
fi

# Create Info.plist
echo "Creating Info.plist..."
cat > "$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.geosub.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Generate Icons
if [ -f "$ICONS_SOURCE" ]; then
    echo "Generating AppIcon.icns from $ICONS_SOURCE..."
    mkdir "$ICON_SET"
    
    # Generate various sizes
    sips -s format png -z 16 16     "$ICONS_SOURCE" --out "$ICON_SET/icon_16x16.png" > /dev/null
    sips -s format png -z 32 32     "$ICONS_SOURCE" --out "$ICON_SET/icon_16x16@2x.png" > /dev/null
    sips -s format png -z 32 32     "$ICONS_SOURCE" --out "$ICON_SET/icon_32x32.png" > /dev/null
    sips -s format png -z 64 64     "$ICONS_SOURCE" --out "$ICON_SET/icon_32x32@2x.png" > /dev/null
    sips -s format png -z 128 128   "$ICONS_SOURCE" --out "$ICON_SET/icon_128x128.png" > /dev/null
    sips -s format png -z 256 256   "$ICONS_SOURCE" --out "$ICON_SET/icon_128x128@2x.png" > /dev/null
    sips -s format png -z 256 256   "$ICONS_SOURCE" --out "$ICON_SET/icon_256x256.png" > /dev/null
    sips -s format png -z 512 512   "$ICONS_SOURCE" --out "$ICON_SET/icon_256x256@2x.png" > /dev/null
    sips -s format png -z 512 512   "$ICONS_SOURCE" --out "$ICON_SET/icon_512x512.png" > /dev/null
    sips -s format png -z 1024 1024 "$ICONS_SOURCE" --out "$ICON_SET/icon_512x512@2x.png" > /dev/null
    
    # Create icns file
    iconutil -c icns "$ICON_SET"
    
    # Move to Resources
    mv "AppIcon.icns" "$APP_NAME.app/Contents/Resources/"
    
    # Cleanup iconset
    rm -rf "$ICON_SET"
else
    echo "Warning: $ICONS_SOURCE not found. Application will use default system icon."
fi

# Ad-hoc Code Signing to avoid permission issues
echo "Signing application..."
codesign --force --deep --sign - "$APP_NAME.app"

echo "=============================================="
echo "Build Successful!"
echo "App is located at: $(pwd)/$APP_NAME.app"
echo "You can move it to /Applications to install it."
echo "=============================================="
