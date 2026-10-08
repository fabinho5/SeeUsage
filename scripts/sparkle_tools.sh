#!/usr/bin/env bash
# Sourced by packaging scripts. Nothing is fetched until ensure_sparkle_tools runs.
SPARKLE_VERSION=2.10.0
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
SPARKLE_TOOLS_DIR="${HOME}/Library/Caches/SeeUsage/Sparkle-${SPARKLE_VERSION}"

ensure_sparkle_tools() {
    local archive="${SPARKLE_TOOLS_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    mkdir -p "$SPARKLE_TOOLS_DIR"
    if [[ ! -f "$archive" ]]; then
        echo "==> Fetching verified Sparkle ${SPARKLE_VERSION} release tools..." >&2
        local temporary_archive
        temporary_archive="$(mktemp "${SPARKLE_TOOLS_DIR}/download.XXXXXXXX")"
        if ! curl --fail --location --retry 3 --silent --show-error \
            "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
            -o "$temporary_archive"; then
            rm -f "$temporary_archive"
            return 1
        fi
        if [[ "$(shasum -a 256 "$temporary_archive" | awk '{print $1}')" != "$SPARKLE_SHA256" ]]; then
            rm -f "$temporary_archive"
            echo "Sparkle archive checksum mismatch." >&2
            return 1
        fi
        mv "$temporary_archive" "$archive"
    fi
    [[ "$(shasum -a 256 "$archive" | awk '{print $1}')" == "$SPARKLE_SHA256" ]] || {
        echo "Cached Sparkle archive checksum mismatch." >&2; return 1;
    }
    # Always restore tools from the verified archive; retain framework symlinks.
    tar -xf "$archive" -C "$SPARKLE_TOOLS_DIR" Sparkle.framework bin LICENSE
    codesign --verify --deep --strict "${SPARKLE_TOOLS_DIR}/Sparkle.framework"
}
