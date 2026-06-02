#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VidPress"
PRODUCT_NAME="VidPressNative"
CONFIGURATION="${CONFIGURATION:-release}"
APP_PATH="$ROOT/release/$APP_NAME.app"
ZIP_PATH="$ROOT/release/VidPress-native-mac-arm64.zip"

cd "$ROOT"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$PRODUCT_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing Swift build product: $EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_PATH" "$ZIP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$ROOT/release"

cp "$EXECUTABLE" "$APP_PATH/Contents/MacOS/$APP_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

find_binary() {
  local env_key="$1"
  shift

  local env_path="${!env_key:-}"
  if [[ -n "$env_path" && -x "$env_path" ]]; then
    echo "$env_path"
    return 0
  fi

  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

FFMPEG_SOURCE="$(find_binary VIDPRESS_FFMPEG_PATH \
  "$ROOT/node_modules/ffmpeg-static/ffmpeg" \
  /opt/homebrew/bin/ffmpeg \
  /usr/local/bin/ffmpeg || true)"

FFPROBE_SOURCE="$(find_binary VIDPRESS_FFPROBE_PATH \
  "$ROOT/node_modules/ffprobe-static/bin/darwin/arm64/ffprobe" \
  "$ROOT/node_modules/ffprobe-static/bin/darwin/x64/ffprobe" \
  /opt/homebrew/bin/ffprobe \
  /usr/local/bin/ffprobe || true)"

if [[ -n "$FFMPEG_SOURCE" ]]; then
  cp "$FFMPEG_SOURCE" "$APP_PATH/Contents/Resources/ffmpeg"
  chmod +x "$APP_PATH/Contents/Resources/ffmpeg"
else
  echo "Warning: FFmpeg was not bundled. The app will look for a system ffmpeg at runtime." >&2
fi

if [[ -n "$FFPROBE_SOURCE" ]]; then
  cp "$FFPROBE_SOURCE" "$APP_PATH/Contents/Resources/ffprobe"
  chmod +x "$APP_PATH/Contents/Resources/ffprobe"
else
  echo "Warning: FFprobe was not bundled. The app will look for a system ffprobe at runtime." >&2
fi

mkdir -p "$APP_PATH/Contents/Resources/Licenses"
for license_file in \
  "$ROOT/node_modules/ffmpeg-static/ffmpeg.LICENSE" \
  "$ROOT/node_modules/ffmpeg-static/LICENSE" \
  "$ROOT/node_modules/ffprobe-static/LICENSE"; do
  if [[ -f "$license_file" ]]; then
    cp "$license_file" "$APP_PATH/Contents/Resources/Licenses/$(basename "$license_file")"
  fi
done

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>VidPress</string>
  <key>CFBundleExecutable</key>
  <string>VidPress</string>
  <key>CFBundleIdentifier</key>
  <string>com.zypher.vidpress</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>VidPress</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.3.0</string>
  <key>CFBundleVersion</key>
  <string>0.3.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.video</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_PATH" >/dev/null
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Built $APP_PATH"
echo "Packed $ZIP_PATH"
