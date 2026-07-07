#!/bin/bash
# Seed Cloud storage+ and TagBankHighlightSync settings for local WebDAV (dev emulator).
#
# Usage:
#   bash configure-emulator-webdav.sh
#   WEBDAV_URL=http://127.0.0.1:8181/ bash configure-emulator-webdav.sh
#
# Environment:
#   KOREADER_DIR   Emulator root (default: ~/koreader-dev/emulator/usr/lib/koreader)
#   WEBDAV_URL     Override auto-detected WebDAV base URL (must end with /)
#   WEBDAV_NAME    Display name for the server (default: Local WebDAV)
#   SKIP_UPLOAD_TEST  Set to 1 to skip curl upload probe

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KOREADER="${KOREADER_DIR:-$HOME/koreader-dev/emulator/usr/lib/koreader}"
SETTINGS_DIR="$KOREADER/settings"
READER_SETTINGS="$KOREADER/settings.reader.lua"
CLOUD_SETTINGS="$SETTINGS_DIR/cloudstorage.lua"
WEBDAV_NAME="${WEBDAV_NAME:-Local WebDAV}"
HIGHLIGHTS_WIN="/mnt/c/Users/small/Desktop/KOReader Highlights"

probe_webdav() {
    local url="$1"
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "${url%/}/" 2>/dev/null || echo "000"
}

detect_webdav_url() {
    if [ -n "${WEBDAV_URL:-}" ]; then
        printf '%s' "$WEBDAV_URL"
        return 0
    fi
    local code host candidates=(
        "http://127.0.0.1:8181/"
        "http://localhost:8181/"
    )
    if command -v ip >/dev/null 2>&1; then
        host="$(ip route show default 2>/dev/null | awk '{print $3}')"
        if [ -n "$host" ]; then
            candidates+=("http://${host}:8181/")
        fi
    fi
    candidates+=(
        "http://192.168.4.123:8181/"
    )
    local url
    for url in "${candidates[@]}"; do
        code="$(probe_webdav "$url")"
        if [ "$code" = "207" ] || [ "$code" = "200" ]; then
            echo "Detected WebDAV at $url (HTTP $code)" >&2
            printf '%s' "$url"
            return 0
        fi
    done
    echo "ERROR: WebDAV not reachable on port 8181 from this environment." >&2
    echo "       On Windows run: cd \"$HIGHLIGHTS_WIN\" && .\\setup-webdav.ps1" >&2
    echo "       Then retry, or set WEBDAV_URL explicitly." >&2
    exit 1
}

ensure_cloudstorage_plugin() {
    if [ -f "$KOREADER/plugins/cloudstorage.koplugin/main.lua" ]; then
        return 0
    fi
    echo "Installing cloudstorage.koplugin…" >&2
    KOREADER_DIR="$KOREADER" bash "$SCRIPT_DIR/setup-emulator-cloud.sh"
}

write_cloudstorage_settings() {
    local url="$1"
    mkdir -p "$SETTINGS_DIR"
    cat > "$CLOUD_SETTINGS" <<EOF
-- ./settings/cloudstorage.lua (seeded by configure-emulator-webdav.sh)
return {
    ["cs_servers"] = {
        [1] = {
            ["address"] = "$url",
            ["name"] = "$WEBDAV_NAME",
            ["password"] = "",
            ["type"] = "webdav",
            ["username"] = "",
        },
    },
}
EOF
    echo "Wrote $CLOUD_SETTINGS" >&2
}

patch_reader_settings() {
    local url="$1"
    local patch_sh="$SCRIPT_DIR/patch-emulator-settings.sh"
    if [ ! -f "$patch_sh" ]; then
        echo "ERROR: Missing $patch_sh" >&2
        exit 1
    fi
    WEBDAV_URL="$url" WEBDAV_NAME="$WEBDAV_NAME" FILE="$READER_SETTINGS" bash "$patch_sh"
}

upload_probe() {
    local url="$1"
    if [ "${SKIP_UPLOAD_TEST:-0}" = "1" ]; then
        return 0
    fi
    local probe="$HIGHLIGHTS_WIN/.highlightsync-probe.json"
    local remote="highlightsync-probe.json"
    mkdir -p "$HIGHLIGHTS_WIN"
    echo '{"probe":true,"source":"configure-emulator-webdav.sh"}' > "$probe"
    local code
    code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
        -T "$probe" "${url%/}/$remote" 2>/dev/null || echo "000")"
    rm -f "$probe"
    curl -s -o /dev/null -X DELETE "${url%/}/$remote" 2>/dev/null || true
    if [ "$code" != "201" ] && [ "$code" != "204" ] && [ "$code" != "200" ]; then
        echo "WARNING: WebDAV upload probe returned HTTP $code (expected 201/204)." >&2
        echo "         Add permissions: CRUD to webdav.yaml and restart WebDAV (setup-webdav.ps1)." >&2
        return 0
    fi
    echo "Upload probe OK (temporary file removed from WebDAV root)." >&2
}

main() {
    if [ ! -d "$KOREADER" ]; then
        echo "ERROR: KOReader emulator not found at: $KOREADER" >&2
        exit 1
    fi
    cd "$KOREADER"
    ensure_cloudstorage_plugin
    local url
    url="$(detect_webdav_url)"
    write_cloudstorage_settings "$url"
    patch_reader_settings "$url"
    upload_probe "$url"
    echo "" >&2
    echo "Emulator WebDAV configuration complete." >&2
    echo "  Cloud storage+ account: $WEBDAV_NAME → $url" >&2
    echo "  TagBankHighlightSync cloud folder: / (root)" >&2
    echo "  Plugins: cloudstorage + tagbankhighlightsync enabled" >&2
    echo "" >&2
    echo "Launch: bash dev-start.sh --emulator /mnt/c/Users/small/AnkiKOAi.koplugin/alice.epub" >&2
}

main "$@"
