# Sourced by bundle.sh and release.sh. Builds the release binary and assembles an
# UNSIGNED build/MemLens.app. Caller must cd to the package root first.

APP="build/MemLens.app"

assemble_app() {
  local version="$1"
  swift build -c release
  local bin
  bin="$(swift build -c release --show-bin-path)/MemLensApp"

  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$bin" "$APP/Contents/MacOS/MemLens"
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MemLens</string>
    <key>CFBundleDisplayName</key><string>MemLens</string>
    <key>CFBundleIdentifier</key><string>io.github.kyoangel.memlens</string>
    <key>CFBundleExecutable</key><string>MemLens</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>${version}</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
}
