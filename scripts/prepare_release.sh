#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/sparkle_tools.sh"

if [[ $# != 2 || "$1" != --dmg ]]; then
    cat <<'HELP'
Usage: ./scripts/prepare_release.sh --dmg PATH

After building (and optionally notarizing/stapling) the final universal DMG,
create appcast.xml and a checksum beside it. Reads public settings in release.json.
The signing key stays in the login Keychain. This never publishes a release.
HELP
    [[ $# == 1 && "$1" == --help ]] && exit 0
    exit 1
fi
[[ "$(uname -s)" == Darwin ]] || { echo "Requires macOS." >&2; exit 1; }
DMG="$2"
[[ -f "$DMG" ]] || { echo "DMG not found: $DMG" >&2; exit 1; }
DMG_DIR="$(cd "$(dirname "$DMG")" && pwd)"
DMG="${DMG_DIR}/$(basename "$DMG")"
VERSION="$(python3 "${SCRIPT_DIR}/release_metadata.py" version)"
ACCOUNT="$(python3 "${SCRIPT_DIR}/release_metadata.py" signingAccount)"
PUBLIC_KEY="$(python3 "${SCRIPT_DIR}/release_metadata.py" publicKey)"
[[ "$(basename "$DMG")" == "SeeUsage-${VERSION}-universal.dmg" ]] || {
    echo "Expected SeeUsage-${VERSION}-universal.dmg; use a versioned universal release." >&2; exit 1;
}
ensure_sparkle_tools
[[ "$("${SPARKLE_TOOLS_DIR}/bin/generate_keys" --account "$ACCOUNT" -p)" == "$PUBLIC_KEY" ]] || {
    echo "The Keychain signing key does not match release.json. No files were signed." >&2; exit 1;
}
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/seeusage-release.XXXXXXXX")"
MOUNT_POINT="${WORK_DIR}/mounted"
MOUNTED=false
cleanup() {
    if [[ "$MOUNTED" == true ]]; then hdiutil detach "$MOUNT_POINT" -quiet || true; fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$MOUNT_POINT" "${WORK_DIR}/archives"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_POINT" -quiet
MOUNTED=true
APP="${MOUNT_POINT}/SeeUsage.app"
python3 "${SCRIPT_DIR}/release_metadata.py" validate-app "$APP"
[[ "$(xcrun lipo -archs "${APP}/Contents/MacOS/SeeUsage")" == *arm64* && \
   "$(xcrun lipo -archs "${APP}/Contents/MacOS/SeeUsage")" == *x86_64* ]] || {
    echo "Both release architectures are required." >&2; exit 1;
}
codesign --verify --deep --strict "$APP"
hdiutil detach "$MOUNT_POINT" -quiet
MOUNTED=false
SIGNATURE="$("${SPARKLE_TOOLS_DIR}/bin/sign_update" --account "$ACCOUNT" -p "$DMG")"
python3 "${SCRIPT_DIR}/release_metadata.py" appcast "$DMG" "$SIGNATURE" "${WORK_DIR}/appcast.xml"
"${SPARKLE_TOOLS_DIR}/bin/sign_update" --account "$ACCOUNT" "${WORK_DIR}/appcast.xml"
"${SPARKLE_TOOLS_DIR}/bin/sign_update" --account "$ACCOUNT" --verify "${WORK_DIR}/appcast.xml"
(cd "$DMG_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
mv -f "${WORK_DIR}/appcast.xml" "${DMG_DIR}/appcast.xml"
echo "==> Prepared signed appcast: ${DMG_DIR}/appcast.xml"
echo "==> Upload the DMG, its .sha256 file, and appcast.xml to the same stable v${VERSION} release."
echo "==> Nothing has been published. Do not modify the DMG or appcast after signing."
