#!/bin/bash
# Sync both plugins and launch KOReader once (delegates to AnkiKoFlash dev-start.sh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TAGBANKHIGHLIGHTSYNC_SRC="${TAGBANKHIGHLIGHTSYNC_SRC:-$SCRIPT_DIR}"
export ANKIKOFLASH_SRC="${ANKIKOFLASH_SRC:-$(dirname "$SCRIPT_DIR")/AnkiKoFlash.koplugin}"
exec bash "$ANKIKOFLASH_SRC/dev-start.sh" "$@"
