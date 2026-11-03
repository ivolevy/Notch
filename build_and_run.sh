#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Notch"
APP_BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ZIP_FILE="${SCRIPT_DIR}/${APP_NAME}.zip"

echo "==> [1/6] Compilando ${APP_NAME} en modo release..."
mkdir -p "${SCRIPT_DIR}/.build/release"
if swift build -c release 2>/dev/null; then
    BINARY_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
else
    echo "    (Usando compilador directo swiftc -O para CommandLineTools en macOS 12)..."
    ARCH="$(uname -m)"
    SDK_PATH="$(xcrun --show-sdk-path)"
    swiftc -O \
        -target "${ARCH}-apple-macosx12.0" \
        -sdk "$SDK_PATH" \
        $(find "${SCRIPT_DIR}/Sources/DynamicNotch" -name "*.swift") \
        -framework AppKit \
        -framework SwiftUI \
        -framework Vision \
        -framework AVFoundation \
        -framework CoreImage \
        -framework CoreMedia \
        -framework UniformTypeIdentifiers \
        -framework ScreenCaptureKit \
        -framework IOKit \
        -o "${SCRIPT_DIR}/.build/release/${APP_NAME}"
    BINARY_PATH="${SCRIPT_DIR}/.build/release/${APP_NAME}"
fi
if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Error: No se encontró el binario compilado en $BINARY_PATH"
    exit 1
fi

echo "==> [2/6] Creando estructura del bundle ${APP_NAME}.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>es</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.ivanlevy.dynamicnotch</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Notch usa la cámara para mostrar el mini espejo circular en vivo.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Notch consulta Spotify y Apple Music para mostrar y controlar la canción actual.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Notch usa el micrófono para grabar audio durante la grabación de pantalla.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Notch captura la pantalla para permitir grabaciones de pantalla completas.</string>
</dict>
</plist>
EOF

echo "==> [3/6] Copiando binario compilado e ícono AppIcon.icns a ${APP_NAME}.app..."
cp "$BINARY_PATH" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
if [[ ! -f "${SCRIPT_DIR}/AppIcon.icns" && -f "${SCRIPT_DIR}/generate_icon.swift" ]]; then
    swift "${SCRIPT_DIR}/generate_icon.swift"
    iconutil -c icns "${SCRIPT_DIR}/AppIcon.iconset" -o "${SCRIPT_DIR}/AppIcon.icns"
    rm -rf "${SCRIPT_DIR}/AppIcon.iconset"
fi
if [[ -f "${SCRIPT_DIR}/AppIcon.icns" ]]; then
    cp "${SCRIPT_DIR}/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
# Nota de Optimización: En macOS 14+ (Sonoma / Sequoia), la app utiliza el motor neuronal nativo de Apple Vision
# (VNGenerateForegroundInstanceMaskRequest), logrando máxima calidad sin inflar el bundle con ~210 MB de modelos ONNX.
if [[ -f "${SCRIPT_DIR}/remove_bg_ai.py" ]]; then
    cp "${SCRIPT_DIR}/remove_bg_ai.py" "${RESOURCES_DIR}/remove_bg_ai.py"
    chmod +x "${RESOURCES_DIR}/remove_bg_ai.py"
fi

echo "==> [4/6] Firmando ad-hoc el bundle ${APP_NAME}.app..."
codesign --force --deep --sign - "$APP_BUNDLE"
touch "$APP_BUNDLE"

echo "==> [5/6] Comprimiendo ${APP_NAME}.zip para AirDrop / GitHub Releases..."
rm -f "$ZIP_FILE"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_FILE"

# Limpiamos versiones anteriores con el nombre viejo y dejamos la copia accesible directamente en el Escritorio
rm -rf "${SCRIPT_DIR}/DynamicNotch.app" "${SCRIPT_DIR}/DynamicNotch.zip" "/Users/ivanlevy/Desktop/DynamicNotch.app" 2>/dev/null || true
rm -rf "/Users/ivanlevy/Desktop/${APP_NAME}.app" 2>/dev/null || true
cp -R "$APP_BUNDLE" "/Users/ivanlevy/Desktop/${APP_NAME}.app" 2>/dev/null || true
touch "/Users/ivanlevy/Desktop/${APP_NAME}.app" 2>/dev/null || true

echo "==> [6/6] Lanzando ${APP_NAME}.app..."
pkill -f "DynamicNotch.app/Contents/MacOS/DynamicNotch" 2>/dev/null || true
pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
sleep 0.5
open -n "$APP_BUNDLE"

echo "¡Listo! ${APP_NAME}.app está corriendo en la parte superior de tu pantalla."
