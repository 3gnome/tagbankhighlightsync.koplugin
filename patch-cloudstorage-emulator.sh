#!/bin/bash
# Patches cloudstorage.koplugin for KOReader v2026.03 dev emulator:
#   A) Guard folder_shortcuts.registerShortcut (API absent on v2026.03)
#   B) Vendor frontend/ui/widget/buttonselector.lua when missing from emulator tree
#   C) Patch frontend/datetime.lua with RFC date parsers used by cloudstorage providers
#   D) Fix showFolderChooseDialog when item.url is nil at WebDAV root
#
# Usage: bash patch-cloudstorage-emulator.sh /path/to/main.lua [KOREADER_DIR]
set -euo pipefail

MAIN="${1:?path to cloudstorage main.lua}"
KOREADER="${2:-${KOREADER_DIR:-$HOME/koreader-dev/emulator/usr/lib/koreader}}"
KOREADER_GIT="${KOREADER_GIT:-https://github.com/koreader/koreader.git}"
BUTTONSELECTOR_REF="${BUTTONSELECTOR_REF:-master}"

patch_main_lua() {
    python3 <<PY
from pathlib import Path
import sys

path = Path("${MAIN}")
text = path.read_text(encoding="utf-8")
marker = "if self.ui.folder_shortcuts and self.ui.folder_shortcuts.registerShortcut then"
if marker in text:
    print(f"Already patched main.lua: {path}")
    sys.exit(0)

start = "    self.ui.menu:registerToMainMenu(self)\n"
end = "\nend\n\nfunction Cloud:getProviders()"
if start not in text or end not in text:
    sys.exit("ERROR: Unexpected main.lua layout; cannot patch")

i0 = text.index(start) + len(start)
i1 = text.index(end)
block = text[i0:i1]
if "registerShortcut" not in block:
    sys.exit("ERROR: No registerShortcut calls found")

patched = (
    "    if self.ui.folder_shortcuts and self.ui.folder_shortcuts.registerShortcut then\n"
    + block
    + "    end\n"
)
path.write_text(text[:i0] + patched + text[i1:], encoding="utf-8")
print(f"Patched main.lua: {path}")
PY
}

vendor_buttonselector() {
    local dest="$KOREADER/frontend/ui/widget/buttonselector.lua"
    if [ -f "$dest" ]; then
        echo "OK: buttonselector.lua already present at $dest" >&2
        return 0
    fi

    mkdir -p "$(dirname "$dest")"

    # Prefer git show from an existing koreader clone (no extra sparse-checkout quirks).
    local cs_cache="${KOREADER_DEV_CACHE:-$HOME/koreader-dev/cache}/koreader-cloudstorage-src-master"
    if [ -d "$cs_cache/.git" ]; then
        if git -C "$cs_cache" show "HEAD:frontend/ui/widget/buttonselector.lua" > "$dest" 2>/dev/null \
            && [ -s "$dest" ]; then
            echo "Installed buttonselector.lua → $dest (from cloudstorage cache)" >&2
            return 0
        fi
    fi

    # Raw GitHub fetch (sparse-checkout of a single file fails on some git versions).
    local ref="${BUTTONSELECTOR_REF:-master}"
    local url="https://raw.githubusercontent.com/koreader/koreader/${ref}/frontend/ui/widget/buttonselector.lua"
    echo "Fetching buttonselector.lua from $url …" >&2
    if ! curl -fsSL "$url" -o "$dest" 2>/dev/null || [ ! -s "$dest" ]; then
        url="https://raw.githubusercontent.com/koreader/koreader/master/frontend/ui/widget/buttonselector.lua"
        echo "Retrying from master…" >&2
        if ! curl -fsSL "$url" -o "$dest" 2>/dev/null || [ ! -s "$dest" ]; then
            echo "ERROR: Could not obtain buttonselector.lua from upstream" >&2
            exit 1
        fi
    fi

    echo "Installed buttonselector.lua → $dest" >&2
}

patch_datetime_compat() {
    local dest="$KOREADER/frontend/datetime.lua"
    if [ ! -f "$dest" ]; then
        echo "ERROR: missing $dest" >&2
        exit 1
    fi
    if grep -q 'function datetime.stringRFC1123ToSeconds' "$dest"; then
        echo "OK: datetime RFC parsers already present in $dest" >&2
        return 0
    fi

    python3 <<PY
from pathlib import Path

path = Path("${dest}")
text = path.read_text(encoding="utf-8")
marker = "function datetime.stringRFC1123ToSeconds"
if marker in text:
    print(f"Already patched datetime: {path}")
    raise SystemExit(0)

block = '''
--- Converts a date+time RFC 1123 string to seconds (cloudstorage compat for v2026.03 emulator)
---- @string "Fri, 20 Mar 2026 11:05:30 GMT"
---- @treturn seconds
function datetime.stringRFC1123ToSeconds(datetime_string)
    local months = { Jan=1, Feb=2, Mar=3, Apr=4, May=5, Jun=6, Jul=7, Aug=8, Sep=9, Oct=10, Nov=11, Dec=12 }
    local day, month, year, hour, mins, sec = datetime_string:match("(%d+) (%a+) (%d+) (%d+):(%d+):(%d+)")
    return os.time({ year = year, month = months[month], day = day, hour = hour, min = mins, sec = sec })
end

--- Converts a date+time RFC 3659 string to seconds (cloudstorage compat for v2026.03 emulator)
---- @string "20260320110530"
---- @treturn seconds
function datetime.stringRFC3659ToSeconds(datetime_string)
    local year, month, day, hour, mins, sec = datetime_string:match("(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)")
    return os.time({ year = year, month = month, day = day, hour = hour, min = mins, sec = sec })
end

--- Converts a date+time ISO 8601 string to seconds (cloudstorage compat for v2026.03 emulator)
---- @string "2026-03-20T11:05:30Z"
---- @treturn seconds
function datetime.stringISO8601ToSeconds(datetime_string)
    local year, month, day, hour, mins, sec = datetime_string:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    return os.time({ year = year, month = month, day = day, hour = hour, min = mins, sec = sec })
end

'''
needle = "\nreturn datetime"
if needle not in text:
    raise SystemExit("ERROR: Unexpected datetime.lua layout; cannot patch")

path.write_text(text.replace(needle, block + needle, 1), encoding="utf-8")
print(f"Patched datetime RFC parsers: {path}")
PY
}

patch_cloudstorage_lua() {
    local cloud_lua
    cloud_lua="$(dirname "$MAIN")/cloudstorage.lua"
    if [ ! -f "$cloud_lua" ]; then
        echo "WARNING: $cloud_lua not found; skipping folder-choose patch" >&2
        return 0
    fi

    python3 <<PY
from pathlib import Path

path = Path("${cloud_lua}")
text = path.read_text(encoding="utf-8")
marker = "if url == nil or url == \"\" then"
if marker in text:
    print(f"Already patched showFolderChooseDialog: {path}")
    raise SystemExit(0)

old = '''function CloudStorage:showFolderChooseDialog(item)
    local url = item.url == "" and "/" or item.url'''
new = '''function CloudStorage:showFolderChooseDialog(item)
    local url = item.url
    if url == nil or url == "" then
        url = "/"
    end'''
if old not in text:
    raise SystemExit("ERROR: Unexpected cloudstorage.lua layout; cannot patch showFolderChooseDialog")

text = text.replace(old, new, 1)
text = text.replace("                                url      = item.url,", "                                url      = url,", 1)
text = text.replace("                            self.choose_folder_callback(item.url)", "                            self.choose_folder_callback(url)", 1)
path.write_text(text, encoding="utf-8")
print(f"Patched showFolderChooseDialog: {path}")
PY
}

patch_sync_silent_success() {
    python3 <<PY
from pathlib import Path

path = Path("${MAIN}")
text = path.read_text(encoding="utf-8")
marker = "tagbank silent sync patch"
if marker in text:
    print(f"Already patched sync silent success: {path}")
    raise SystemExit(0)

old = '''                UIManager:show(Notification:new{
                    text = _("Successfully synchronized."),
                    timeout = 2,
                })'''
new = '''                -- tagbank silent sync patch
                if not is_silent then
                    UIManager:show(Notification:new{
                        text = _("Successfully synchronized."),
                        timeout = 2,
                    })
                end'''
if old not in text:
    raise SystemExit("ERROR: Unexpected main.lua layout; cannot patch sync silent success")

path.write_text(text.replace(old, new, 1), encoding="utf-8")
print(f"Patched sync silent success: {path}")
PY
}

patch_main_lua
vendor_buttonselector
patch_datetime_compat
patch_cloudstorage_lua
patch_sync_silent_success
