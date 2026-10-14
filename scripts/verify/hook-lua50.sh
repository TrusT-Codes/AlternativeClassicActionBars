#!/bin/bash
# PostToolUse hook: luac50 -p + lint50 on an edited .lua that is listed in a .toc; exit 2 with errors on stderr on failure.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$HERE/../.." && pwd)}"
LUAC50="${LUAC50:-$(command -v luac50 || command -v /c/Tools/lua50/luac50.exe)}"
LUA50="${LUA50:-$(command -v lua50 || command -v /c/Tools/lua50/lua50.exe)}"
FILE=$(py -3 -I -c 'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("file_path",""))' | tr -d '\r' | tr '\\' '/')
case "$FILE" in *.lua|*.LUA) ;; *) exit 0 ;; esac
ROOTW=$(cd "$ROOT" && pwd -W 2>/dev/null || pwd)
REL="$FILE"
for R in "$ROOTW" "$ROOT"; do
  LOWF="${FILE,,}"; LOWR="${R,,}/"
  [ "${LOWF#"$LOWR"}" != "$LOWF" ] && REL="${FILE:${#LOWR}}"
done
cat "$ROOT"/*.toc 2>/dev/null | tr -d '\r' | tr '\\' '/' | awk -v f="$REL" 'tolower($0) == tolower(f) { found = 1 } END { exit !found }' || exit 0
if [ -z "$LUAC50" ] || [ -z "$LUA50" ]; then echo "WARNING: Lua 5.0 compiler missing, $REL not checked" >&2; exit 0; fi
cd "$ROOT"
ERR=$("$LUAC50" -p "$REL" 2>&1) || { echo "$ERR" >&2; exit 2; }
ERR=$("$LUA50" "$HERE/lint50.lua" "$REL" 2>&1) || { echo "$ERR" >&2; exit 2; }
exit 0
