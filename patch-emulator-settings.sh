#!/bin/bash
# Insert sync_server into emulator settings.reader.lua (no luajit required).
set -euo pipefail
KOREADER="${KOREADER_DIR:-$HOME/koreader-dev/emulator/usr/lib/koreader}"
FILE="$KOREADER/settings.reader.lua"
URL="${WEBDAV_URL:-http://127.0.0.1:8181/}"
NAME="${WEBDAV_NAME:-Local WebDAV}"

if grep -q 'sync_server' "$FILE" 2>/dev/null; then
    echo "sync_server already present in $FILE" >&2
    exit 0
fi

export FILE="$FILE"
export WEBDAV_URL="$URL"
export WEBDAV_NAME="$NAME"

python3 <<PY
import os
from pathlib import Path

path = Path(os.environ["FILE"])
url = os.environ["WEBDAV_URL"]
name = os.environ["WEBDAV_NAME"]
text = path.read_text(encoding="utf-8")
block = f'''        ["sync_server"] = {{
            ["address"] = "{url}",
            ["name"] = "{name}",
            ["password"] = "",
            ["type"] = "webdav",
            ["username"] = "",
            ["url"] = "/",
        }},
'''
needle = '        ["sync_on_resume"] = false,'
if needle not in text:
    raise SystemExit("Could not find sync_on_resume anchor in settings.reader.lua")
text = text.replace(needle, needle + "\n" + block, 1)
path.write_text(text, encoding="utf-8")
print(f"Patched {path}")
PY
