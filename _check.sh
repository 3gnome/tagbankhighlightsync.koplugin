#!/bin/bash
# Dev-only syntax/sanity checker (not part of the plugin).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KO="${KOREADER_DIR:-$HOME/koreader-dev/emulator/usr/lib/koreader}"
SRC="${PLUGIN_DIR:-$SCRIPT_DIR}"
LJ="$KO/luajit"
fail=0

if [ ! -x "$LJ" ]; then
    echo "ERROR: Emulator luajit not found at: $LJ" >&2
    echo "Set KOREADER_DIR or install the KOReader dev emulator." >&2
    exit 1
fi

echo "=== Parse-check all .lua files (loadfile, parse only) ==="
while IFS= read -r f; do
    CHK="$f" "$LJ" -e 'local p=os.getenv("CHK"); local fn,e=loadfile(p); if not fn then io.stderr:write(tostring(e).."\n"); os.exit(1) end' 2>/tmp/_chk.err
    if [ $? -ne 0 ]; then
        echo "SYNTAX ERROR: $f"
        cat /tmp/_chk.err
        fail=1
    fi
done < <(find "$SRC" -name '*.lua' -not -path '*/.git/*')
[ "$fail" -eq 0 ] && echo "All .lua files parse OK"

exit "$fail"
