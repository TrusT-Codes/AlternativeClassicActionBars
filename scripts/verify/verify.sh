#!/bin/bash
# usage: verify.sh <repoRoot> <outDir>   writes syntax/lint/inventory/globals/upvalues reports into outDir; also regenerates docs/symbols.txt
# Syntax via Lua 5.0 luac50 (falls back to 5.1 luac with a warning), lint via lua50 + the vanilla-wow-addon skill's lint50.lua (or set LINT50).
# Needs Lua 5.1 luac on PATH for listings; set LUA to the 5.1 interpreter if it isn't on PATH as lua/lua.exe/lua5.1.
ROOT="$1"; mkdir -p "$2"; OUT="$(cd "$2" && pwd)"; HERE="$(cd "$(dirname "$0")" && pwd)"
LUA="${LUA:-$(command -v lua || command -v lua.exe || command -v lua5.1)}"
LUAC50="${LUAC50:-$(command -v luac50 || command -v /c/Tools/lua50/luac50.exe)}"
LUA50="${LUA50:-$(command -v lua50 || command -v /c/Tools/lua50/lua50.exe)}"
LINT50="${LINT50:-$HOME/.claude/skills/vanilla-wow-addon/scripts/lint50.lua}"
FILES=$(grep -E '^[A-Za-z].*\.lua' "$ROOT/AlternativeClassicActionBars.toc" | tr -d '\r')
cd "$ROOT"
if [ -n "$LUAC50" ]; then
  "$LUAC50" -p $FILES > "$OUT/syntax.txt" 2>&1 && echo "SYNTAX OK" >> "$OUT/syntax.txt"
else
  echo "WARNING: Lua 5.0 compiler missing" | tee "$OUT/syntax.txt"
  luac -p $FILES >> "$OUT/syntax.txt" 2>&1 && echo "SYNTAX OK" >> "$OUT/syntax.txt"
fi
if [ -z "$LUA50" ]; then echo "WARNING: lua50 missing, lint50 skipped" > "$OUT/lint50.txt"
elif [ ! -f "$LINT50" ]; then echo "WARNING: $LINT50 missing, lint50 skipped" > "$OUT/lint50.txt"
else "$LUA50" "$LINT50" $FILES > "$OUT/lint50.txt" 2>&1; fi
"$LUA" "$HERE/load.lua" "$ROOT" > "$OUT/inventory.txt" 2>&1
for f in $FILES; do luac -l -p $f | grep -oE '(GET|SET)GLOBAL.*; [A-Za-z_][A-Za-z0-9_]*' | sed -E 's/^(GET|SET)GLOBAL.*; /\1 /'; done | sort -u > "$OUT/globals.txt"
for f in $FILES; do luac -l -l -p $f | grep -E '^[0-9]+\+? params?, .* upvalues?' | sed -E 's/.*, ([0-9]+) upvalues?.*/\1/' ; done | sort -n | tail -1 > "$OUT/maxupvalues.txt"
grep -q -E '^(LOADERR|RUNERR)' "$OUT/inventory.txt" && echo "LOAD FAILED: $(head -1 "$OUT/inventory.txt")" || echo "load ok ($(wc -l < "$OUT/inventory.txt") inventory entries)"
bash "$HERE/../symbols.sh" "$ROOT"
cat "$OUT/syntax.txt" | tail -1; cat "$OUT/lint50.txt"; echo "max upvalues: $(cat "$OUT/maxupvalues.txt")"; echo "globals: $(wc -l < "$OUT/globals.txt")"
