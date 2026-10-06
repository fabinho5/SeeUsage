#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

echo "==> Compiling SeeUsage in release mode..."
if command -v conda >/dev/null 2>&1 && conda env list | grep -q "seeu"; then
    conda run -n seeu swift build -c release
else
    swift build -c release
fi

BIN_PATH="${ROOT_DIR}/.build/release/SeeUsage"
DIST_DIR="${ROOT_DIR}/dist"
# Keep development bundles out of Spotlight and the macOS Apps list.
APP_DIR="${DIST_DIR}/build.noindex/SeeUsage.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

LEGACY_APP_DIR="${DIST_DIR}/SeeUsage.app"
if [[ -d "${LEGACY_APP_DIR}" ]]; then
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [[ -x "${LSREGISTER}" ]]; then
        "${LSREGISTER}" -u "${LEGACY_APP_DIR}" 2>/dev/null || true
    fi
    rm -rf "${LEGACY_APP_DIR}"
fi

echo "==> Packaging ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/SeeUsage"
chmod +x "${MACOS_DIR}/SeeUsage"

cp -R "${ROOT_DIR}/Sources/SeeUsage/Resources/Companion" "${RESOURCES_DIR}/Companion"

cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SeeUsage</string>
    <key>CFBundleIdentifier</key>
    <string>app.seeusage.SeeUsage</string>
    <key>CFBundleName</key>
    <string>SeeUsage</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
    echo "==> Signing ad-hoc..."
    codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true
fi

echo "==> Built: ${APP_DIR}"
