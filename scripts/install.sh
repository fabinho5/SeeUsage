#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

"${SCRIPT_DIR}/build_app.sh"

if [[ -w /Applications ]]; then
    DEST_DIR="/Applications"
else
    DEST_DIR="${HOME}/Applications"
fi
mkdir -p "${DEST_DIR}"

# Terminate existing running instances so new binary takes over immediately
killall -9 SeeUsage seeusage 2>/dev/null || true
rm -f "${HOME}/.config/seeusage/app.lock"

echo "==> Installing SeeUsage.app to ${DEST_DIR}..."
rm -rf "${DEST_DIR}/SeeUsage.app"
cp -R "${ROOT_DIR}/dist/build.noindex/SeeUsage.app" "${DEST_DIR}/"

echo "==> Successfully installed to ${DEST_DIR}/SeeUsage.app"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
# Preserve earlier user-folder installations without leaving duplicate search results.
if [[ "${DEST_DIR}" == "/Applications" ]]; then
    for LEGACY_APP in "${HOME}/Applications/SeeUsage.app" "${HOME}/Applications/SeeUsage.app.previous"; do
        if [[ -d "${LEGACY_APP}" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${LEGACY_APP}/Contents/Info.plist" 2>/dev/null || true)" == "app.seeusage.SeeUsage" ]]; then
            BACKUP_DIR="${HOME}/.local/share/seeusage/backups.noindex"
            mkdir -p "${BACKUP_DIR}"
            BACKUP_SLOT="$(mktemp -d "${BACKUP_DIR}/install-XXXXXXXX")"
            if [[ -x "${LSREGISTER}" ]]; then
                "${LSREGISTER}" -u "${LEGACY_APP}" 2>/dev/null || true
            fi
            mv "${LEGACY_APP}" "${BACKUP_SLOT}/"
            echo "==> Previous installation preserved in ${BACKUP_SLOT}"
        fi
    done
fi
if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -f "${DEST_DIR}/SeeUsage.app"
fi
if command -v mdimport >/dev/null 2>&1; then
    mdimport -i "${DEST_DIR}/SeeUsage.app"
fi

# Terminal / Shell Integration
CLI_DIR="${HOME}/.local/bin"
mkdir -p "${CLI_DIR}"
ln -sf "${DEST_DIR}/SeeUsage.app/Contents/MacOS/SeeUsage" "${CLI_DIR}/seeusage"
chmod +x "${CLI_DIR}/seeusage"

echo "==> Command 'seeusage' available in your terminal at ${CLI_DIR}/seeusage"
