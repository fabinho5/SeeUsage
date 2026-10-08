#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="$ROOT_DIR"
APP_DIR=""
OUTPUT_PATH=""
SIGN_IDENTITY=""
UNIVERSAL=false
source "${SCRIPT_DIR}/sparkle_tools.sh"

usage() {
    cat <<'HELP'
Usage: ./scripts/build_dmg.sh [options]

Build SeeUsage with the existing build_app.sh, then package a drag-to-install DMG.

  --universal       Include Apple Silicon and Intel binaries.
  --app PATH        Package an existing SeeUsage.app without rebuilding it.
  --output PATH     Write the DMG here (default: dist, or Downloads if not writable).
  --sign IDENTITY   Sign the copied app and DMG with a Developer ID identity.
  --help            Show this help.

With --app, --universal requires an app that already contains both architectures.
Source builds use a writable cache in ~/Library/Caches/SeeUsage/dmg-build.
New builds include Sparkle updates and use version/signing settings in release.json.
Prebuilt --app bundles retain their existing version and updater configuration.
The app includes the CLI executable; DMG installation does not create its shell link.
Developer ID signing and Apple notarization are separate from ad-hoc local builds.
HELP
}

fail() { echo "Error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --universal) UNIVERSAL=true; shift ;;
        --app|--output|--sign)
            [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "$1 requires a value."
            case "$1" in
                --app) APP_DIR="$2" ;;
                --output) OUTPUT_PATH="$2" ;;
                --sign) SIGN_IDENTITY="$2" ;;
            esac
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1 (use --help)." ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || fail "DMG packaging requires macOS."
for tool in hdiutil codesign ditto xcrun shasum python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required tool not found: $tool"
done

PREBUILT=false
if [[ -n "$APP_DIR" ]]; then
    PREBUILT=true
else
    VERSION="$(python3 "${SCRIPT_DIR}/release_metadata.py" version)"
    ensure_sparkle_tools
    command -v rsync >/dev/null 2>&1 || fail "Required tool not found: rsync"
    # Keep the original builder intact and avoid checkout caches owned by another user.
    SOURCE_KEY="$(printf '%s' "$ROOT_DIR" | shasum -a 256 | awk '{ print $1 }')"
    BUILD_ROOT="${HOME}/Library/Caches/SeeUsage/dmg-build/${SOURCE_KEY}"
    mkdir -p "${BUILD_ROOT}/scripts"
    for SOURCE_DIR in Sources Tests; do
        rsync -a --delete "${ROOT_DIR}/${SOURCE_DIR}/" "${BUILD_ROOT}/${SOURCE_DIR}/"
    done
    cp -p "${ROOT_DIR}/Package.swift" "${BUILD_ROOT}/Package.swift"
    cp -p "${SCRIPT_DIR}/build_app.sh" "${BUILD_ROOT}/scripts/build_app.sh"
    if [[ -f "${ROOT_DIR}/Package.resolved" ]]; then
        cp -p "${ROOT_DIR}/Package.resolved" "${BUILD_ROOT}/Package.resolved"
    else
        rm -f "${BUILD_ROOT}/Package.resolved"
    fi
    echo "==> Using writable build cache: $BUILD_ROOT"
    # Public dependencies need no credentials. Avoid SwiftPM asking to read a
    # publisher's GitHub token from Keychain when fetching the binary artifact.
    SEEUSAGE_ENABLE_SPARKLE=1 swift package --package-path "$BUILD_ROOT" --disable-keychain --disable-netrc resolve
    SEEUSAGE_ENABLE_SPARKLE=1 "${BUILD_ROOT}/scripts/build_app.sh"
    APP_DIR="${BUILD_ROOT}/dist/build.noindex/SeeUsage.app"
fi
[[ -d "$APP_DIR" ]] || fail "App bundle not found: $APP_DIR"
APP_DIR="$(cd "$APP_DIR" && pwd)"
PLIST="${APP_DIR}/Contents/Info.plist"
[[ -f "$PLIST" && -x "${APP_DIR}/Contents/MacOS/SeeUsage" ]] || fail "Incomplete SeeUsage.app."
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
[[ "$BUNDLE_ID" == "app.seeusage.SeeUsage" ]] || fail "This is not a SeeUsage app bundle."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
case "$VERSION" in ""|*[!0-9A-Za-z._-]*) fail "Invalid app version: $VERSION" ;; esac

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/seeusage-dmg.XXXXXXXX")"
OUTPUT_TEMP_DIR=""
cleanup() {
    rm -rf "$WORK_DIR"
    if [[ -n "$OUTPUT_TEMP_DIR" ]]; then rm -rf "$OUTPUT_TEMP_DIR"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

CONTENTS_DIR="${WORK_DIR}/contents"
mkdir -p "$CONTENTS_DIR"
STAGED_APP="${CONTENTS_DIR}/SeeUsage.app"
ditto "$APP_DIR" "$STAGED_APP"
STAGED_BIN="${STAGED_APP}/Contents/MacOS/SeeUsage"
APP_CHANGED=false
if [[ "$PREBUILT" == false ]]; then
    mkdir -p "${STAGED_APP}/Contents/Frameworks"
    ditto "${SPARKLE_TOOLS_DIR}/Sparkle.framework" "${STAGED_APP}/Contents/Frameworks/Sparkle.framework"
    cp "${SPARKLE_TOOLS_DIR}/LICENSE" "${STAGED_APP}/Contents/Resources/Sparkle-LICENSE.txt"
    python3 "${SCRIPT_DIR}/release_metadata.py" configure "$STAGED_APP"
    VERSION="$(python3 "${SCRIPT_DIR}/release_metadata.py" version)"
    APP_CHANGED=true
fi
ARCHS="$(xcrun lipo -archs "$STAGED_BIN")"

if [[ "$UNIVERSAL" == true ]]; then
    BINARIES=()
    NEEDS_UNIVERSAL=false
    SWIFT_COMMAND=(swift)
    if command -v conda >/dev/null 2>&1 && conda env list | awk '$1 == "seeu" { found = 1 } END { exit !found }'; then
        SWIFT_COMMAND=(conda run -n seeu swift)
    fi
    for TARGET_ARCH in arm64 x86_64; do
        case " $ARCHS " in
            *" $TARGET_ARCH "*) BINARIES+=("$STAGED_BIN") ;;
            *)
                [[ "$PREBUILT" == false ]] || fail "The supplied app lacks $TARGET_ARCH. Build with --universal without --app."
                echo "==> Compiling the $TARGET_ARCH release slice..."
                BUILD_ARGS=(-c release --disable-keychain --disable-netrc --package-path "$BUILD_ROOT" --scratch-path "${BUILD_ROOT}/.build/dmg-${TARGET_ARCH}" --triple "${TARGET_ARCH}-apple-macosx14.0")
                SEEUSAGE_ENABLE_SPARKLE=1 "${SWIFT_COMMAND[@]}" build "${BUILD_ARGS[@]}"
                BIN_DIR="$(SEEUSAGE_ENABLE_SPARKLE=1 "${SWIFT_COMMAND[@]}" build "${BUILD_ARGS[@]}" --show-bin-path)"
                BINARIES+=("${BIN_DIR}/SeeUsage")
                NEEDS_UNIVERSAL=true
                APP_CHANGED=true ;;
        esac
    done
    if [[ "$NEEDS_UNIVERSAL" == true ]]; then
        xcrun lipo -create "${BINARIES[@]}" -output "${WORK_DIR}/SeeUsage-universal"
        cp "${WORK_DIR}/SeeUsage-universal" "$STAGED_BIN"
        chmod +x "$STAGED_BIN"
        ARCHS="$(xcrun lipo -archs "$STAGED_BIN")"
    fi
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
    FRAMEWORK="${STAGED_APP}/Contents/Frameworks/Sparkle.framework"
    if [[ -d "$FRAMEWORK" ]]; then
        # Sign nested helpers before their containing framework and host app.
        for HELPER in Autoupdate Updater.app XPCServices/Downloader.xpc XPCServices/Installer.xpc; do
            codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
                --preserve-metadata=entitlements "${FRAMEWORK}/Versions/B/${HELPER}"
        done
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$FRAMEWORK"
    fi
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$STAGED_APP"
elif [[ "$APP_CHANGED" == true ]]; then
    codesign --force --sign - "$STAGED_APP"
fi
codesign --verify --deep --strict "$STAGED_APP"
for SPRITE in idle blink hurt worn critical celebrate; do
    [[ -f "${STAGED_APP}/Contents/Resources/Companion/lume-${SPRITE}.png" ]] || fail "Missing companion artwork: $SPRITE"
done

ARCH_LABEL="$ARCHS"
case " $ARCHS " in *" arm64 "*) case " $ARCHS " in *" x86_64 "*) ARCH_LABEL=universal ;; esac ;; esac
if [[ -z "$OUTPUT_PATH" ]]; then
    DEFAULT_OUTPUT_DIR="${ROOT_DIR}/dist"
    if [[ -d "$DEFAULT_OUTPUT_DIR" && ! -w "$DEFAULT_OUTPUT_DIR" ]] || [[ ! -d "$DEFAULT_OUTPUT_DIR" && ! -w "$ROOT_DIR" ]]; then
        DEFAULT_OUTPUT_DIR="${HOME}/Downloads"
        echo "==> Checkout dist folder is not writable; saving the DMG in Downloads."
    fi
    OUTPUT_PATH="${DEFAULT_OUTPUT_DIR}/SeeUsage-${VERSION}-${ARCH_LABEL}.dmg"
fi
case "$OUTPUT_PATH" in *.dmg) ;; *) fail "The output path must end with .dmg." ;; esac
OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
DMG_NAME="$(basename "$OUTPUT_PATH")"
OUTPUT_PATH="${OUTPUT_DIR}/${DMG_NAME}"
OUTPUT_TEMP_DIR="$(mktemp -d "${OUTPUT_DIR}/.seeusage-dmg.XXXXXXXX")"
TEMP_DMG="${OUTPUT_TEMP_DIR}/${DMG_NAME}"

ln -s /Applications "${CONTENTS_DIR}/Applications"
cat > "${CONTENTS_DIR}/Install SeeUsage.txt" <<'INSTALL'
Install SeeUsage

1. Quit an existing SeeUsage instance before replacing it.
2. Drag SeeUsage.app onto Applications, or copy it into your own ~/Applications.
3. Open SeeUsage from Applications. It appears in the menu bar.
4. Eject this disk image. Fresh installations use the Compact UI profile.

No Swift compiler, Xcode, or Conda is needed to run the packaged app.
Install and sign in to the providers' CLIs to track their quotas.

Optional terminal command (adjust the app path if installed in ~/Applications):

  mkdir -p "$HOME/.local/bin"
  ln -sf "/Applications/SeeUsage.app/Contents/MacOS/SeeUsage" "$HOME/.local/bin/seeusage"
  export PATH="$HOME/.local/bin:$PATH"

For downloads blocked because the developer cannot be verified, follow Apple's
instructions for software you trust:
https://support.apple.com/en-us/102445

Source and releases: https://github.com/fabinho5/SeeUsage
INSTALL

echo "==> Creating ${DMG_NAME}..."
hdiutil create -volname SeeUsage -srcfolder "$CONTENTS_DIR" -fs HFS+ -format UDZO -imagekey zlib-level=9 -nospotlight "$TEMP_DMG"
if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp --identifier app.seeusage.dmg "$TEMP_DMG"
    codesign --verify "$TEMP_DMG"
fi
hdiutil verify "$TEMP_DMG"
(cd "$OUTPUT_TEMP_DIR" && shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256")
mv -f "$TEMP_DMG" "$OUTPUT_PATH"
mv -f "${TEMP_DMG}.sha256" "${OUTPUT_PATH}.sha256"
echo "==> Built: $OUTPUT_PATH"
echo "==> SHA-256: ${OUTPUT_PATH}.sha256"
echo "==> Architectures: $ARCHS"
if [[ "$(codesign -dv "$STAGED_APP" 2>&1)" == *"Signature=adhoc"* ]]; then
    echo "==> App signing: ad-hoc. Use --sign and Apple notarization for a public Developer ID release."
fi
