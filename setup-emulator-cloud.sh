#!/bin/bash
# Install Cloud storage for TagBankHighlightSync on the v2026.03 dev emulator.
# Pins upstream ref (default v2026.03), patches main.lua, vendors buttonselector,
# and validates require('cloudstorage') against the emulator tree.
#
# Usage: bash setup-emulator-cloud.sh
#
# Environment:
#   KOREADER_DIR      Emulator root (default: ~/koreader-dev/emulator/usr/lib/koreader)
#   KOREADER_SRC      Local KOReader repo with plugins/cloudstorage.koplugin (optional)
#   KOREADER_GIT      Upstream URL (default: https://github.com/koreader/koreader.git)
#   KOREADER_REF      Git ref for cloudstorage.koplugin (default: v2026.03; falls back to master)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOREADER="${KOREADER_DIR:-$HOME/koreader-dev/emulator/usr/lib/koreader}"
DEST="$KOREADER/plugins/cloudstorage.koplugin"
KOREADER_GIT="${KOREADER_GIT:-https://github.com/koreader/koreader.git}"
KOREADER_REF="${KOREADER_REF:-v2026.03}"
CACHE="${KOREADER_DEV_CACHE:-$HOME/koreader-dev/cache}/koreader-cloudstorage-src"
PATCH="$SCRIPT_DIR/patch-cloudstorage-emulator.sh"

find_local_source() {
    local candidate
    for candidate in \
        "${KOREADER_SRC:-}" \
        "$HOME/koreader-dev/koreader" \
        "$HOME/koreader" \
        ; do
        if [ -n "$candidate" ] && [ -f "$candidate/plugins/cloudstorage.koplugin/main.lua" ]; then
            printf '%s/plugins/cloudstorage.koplugin' "$candidate"
            return 0
        fi
    done
    return 1
}

fetch_upstream_source_at_ref() {
    local ref="$1"
    local cache="${CACHE}-${ref//\//_}"
    mkdir -p "$(dirname "$cache")"
    echo "Fetching cloudstorage.koplugin from $KOREADER_GIT ($ref, sparse)…" >&2
    rm -rf "$cache"
    if ! git clone --depth 1 --filter=blob:none --sparse --branch "$ref" "$KOREADER_GIT" "$cache" 2>/dev/null; then
        rm -rf "$cache"
        return 1
    fi
    (
        cd "$cache"
        git sparse-checkout set plugins/cloudstorage.koplugin
        git checkout
    ) >&2
    if [ ! -f "$cache/plugins/cloudstorage.koplugin/main.lua" ]; then
        rm -rf "$cache"
        return 1
    fi
    printf '%s/plugins/cloudstorage.koplugin' "$cache"
}

fetch_upstream_source() {
    local src
    if src="$(fetch_upstream_source_at_ref "$KOREADER_REF")"; then
        printf '%s' "$src"
        return 0
    fi
    echo "WARNING: cloudstorage.koplugin not found at ref $KOREADER_REF; trying master…" >&2
    if src="$(fetch_upstream_source_at_ref "master")"; then
        printf '%s' "$src"
        return 0
    fi
    echo "ERROR: sparse checkout did not produce plugins/cloudstorage.koplugin/main.lua" >&2
    exit 1
}

validate_cloudstorage_module() {
    local lj="$KOREADER/luajit"
    local bs="$KOREADER/frontend/ui/widget/buttonselector.lua"
    if [ ! -x "$lj" ]; then
        echo "ERROR: Emulator luajit not found at: $lj" >&2
        exit 1
    fi
    if [ ! -s "$bs" ]; then
        echo "ERROR: missing $bs (Cloud folder tap will fail with buttonselector not found)" >&2
        exit 1
    fi
    local dt="$KOREADER/frontend/datetime.lua"
    if ! grep -q 'function datetime.stringRFC1123ToSeconds' "$dt"; then
        echo "ERROR: missing datetime.stringRFC1123ToSeconds in $dt (WebDAV browse will crash)" >&2
        exit 1
    fi
    cd "$KOREADER"
    export LD_LIBRARY_PATH="./libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    local f
    for f in \
        plugins/cloudstorage.koplugin/main.lua \
        plugins/cloudstorage.koplugin/cloudstorage.lua \
        plugins/cloudstorage.koplugin/providers/webdav.lua \
        frontend/ui/widget/buttonselector.lua \
        frontend/datetime.lua \
        ; do
        if ! FILE="$f" "$lj" -e 'local fn,e=loadfile(os.getenv("FILE")); if not fn then io.stderr:write(tostring(e).."\n"); os.exit(1) end'; then
            echo "ERROR: parse check failed: $f" >&2
            exit 1
        fi
    done
    echo "Load OK: cloudstorage plugin + buttonselector (parse check)" >&2
}

install_plugin() {
    local src="$1"
    if [ ! -d "$KOREADER" ]; then
        echo "ERROR: KOReader emulator not found at: $KOREADER" >&2
        exit 1
    fi
    mkdir -p "$KOREADER/plugins"
    rsync -a --delete "$src/" "$DEST/"
    bash "$PATCH" "$DEST/main.lua" "$KOREADER"
    validate_cloudstorage_module
    echo "Installed Cloud storage → $DEST" >&2
}

main() {
    local src
    if src="$(find_local_source)"; then
        echo "Using local source: $src" >&2
    else
        src="$(fetch_upstream_source)"
        echo "Using upstream source: $src" >&2
    fi
    install_plugin "$src"
    if [ -f "$DEST/main.lua" ] && [ -d "$DEST/providers" ]; then
        echo "OK: cloudstorage.koplugin ready for v2026.03 emulator." >&2
    else
        echo "ERROR: install incomplete — missing main.lua or providers/" >&2
        exit 1
    fi
}

main "$@"
