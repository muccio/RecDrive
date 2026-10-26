#!/bin/bash
set -euo pipefail

# Build script for MacReceiver.app (RecDrive Android Remote Receiver)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "==> Compiling MacReceiver (macOS 13+, arm64/x86_64)..."
SCRATCH_DIR="/tmp/macreceiver-build"
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build \
    -c release \
    --scratch-path "${SCRATCH_DIR}"

BIN_PATH="${SCRATCH_DIR}/out/Products/Release/MacReceiver"
APP_DIR="${SCRIPT_DIR}/bin/MacReceiver.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

if [ -f "${BIN_PATH}" ]; then
    echo "==> Creating MacReceiver.app bundle..."
    rm -rf "${APP_DIR}"
    mkdir -p "${MACOS_DIR}"
    mkdir -p "${RESOURCES_DIR}"
    
    # 1. Executable
    cp "${BIN_PATH}" "${MACOS_DIR}/MacReceiver"
    chmod +x "${MACOS_DIR}/MacReceiver"
    
    # Also keep standalone binary in bin/ for CLI convenience
    cp "${BIN_PATH}" "${SCRIPT_DIR}/bin/MacReceiver"
    chmod +x "${SCRIPT_DIR}/bin/MacReceiver"
    
    # 2. Info.plist
    cp "${SCRIPT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
    
    # 3. AppIcon
    if [ -f "${SCRIPT_DIR}/Resources/AppIcon.icns" ]; then
        cp "${SCRIPT_DIR}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
    fi
    
    # 4. PkgInfo
    echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"
    
    # 5. Ad-hoc code signing for TCC / Accessibility permission tracking
    echo "==> Code signing MacReceiver.app..."
    codesign --force --deep --sign - "${APP_DIR}"
    
    # 6. Create convenient root symlink in MacReceiver/MacReceiver.app
    rm -f "${SCRIPT_DIR}/MacReceiver.app"
    ln -s "bin/MacReceiver.app" "${SCRIPT_DIR}/MacReceiver.app"
    
    echo "=========================================================="
    echo "✓ MacReceiver.app creato con successo!"
    echo "  App bundle: ${APP_DIR}"
    echo "  Symlink:    ${SCRIPT_DIR}/MacReceiver.app"
    echo ""
    echo "Per avviarlo puoi fare doppio clic sull'app nel Finder oppure:"
    echo "  open \"${SCRIPT_DIR}/MacReceiver.app\""
    echo "=========================================================="
else
    echo "Errore: binario non trovato in ${BIN_PATH}"
    exit 1
fi
