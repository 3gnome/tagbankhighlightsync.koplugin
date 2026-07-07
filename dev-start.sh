#!/bin/bash
# Sync both plugins and launch KOReader once (delegates to AnkiKOAi dev-start.sh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TAGBANKHIGHLIGHTSYNC_SRC="${TAGBANKHIGHLIGHTSYNC_SRC:-$SCRIPT_DIR}"
export ANKIKOOAI_SRC="${ANKIKOOAI_SRC:-/mnt/c/Users/small/AnkiKOAi.koplugin}"
exec bash "$ANKIKOOAI_SRC/dev-start.sh" "$@"
