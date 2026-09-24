#!/bin/bash
set -euo pipefail

# RecDrive .app Bundler Script
# Compiles RecDrive with Apple Silicon optimization and packages into RecDrive.app

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_DIR="${BUILD_DIR}/RecDrive.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SCRATCH_DIR="/tmp/recdrive-build"

echo "==> Building RecDrive executable (arm64, macOS 13+)..."
cd "${PROJECT_DIR}"

DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build \
    --configuration release \
    --scratch-path "${SCRATCH_DIR}" \
    -Xswiftc -no-link-objc-runtime

echo "==> Creating macOS App Bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy binary
cp "${SCRATCH_DIR}/out/Products/Release/RecDrive" "${MACOS_DIR}/RecDrive"
chmod +x "${MACOS_DIR}/RecDrive"

# Copy Info.plist and Entitlements
cp "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Ad-hoc codesign with entitlements
echo "==> Applying codesign with entitlements..."
codesign --force --deep --sign - --entitlements "${PROJECT_DIR}/Resources/RecDrive.entitlements" "${APP_DIR}"

echo "=========================================================="
echo "✓ RecDrive.app successfully bundled at:"
echo "  ${APP_DIR}"
echo "  To launch: open ${APP_DIR}"
echo "=========================================================="
