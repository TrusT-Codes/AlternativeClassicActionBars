#!/bin/bash
# usage: verify.sh <repoRoot> <outDir>   writes syntax/inventory/globals/upvalues reports into outDir
# Needs Lua 5.1 luac on PATH; set LUA to the interpreter if it isn't on PATH as lua/lua.exe/lua5.1.
ROOT="$1"; mkdir -p "$2"; OUT="$(cd "$2" && pwd)"; HERE="$(cd "$(dirname "$0")" && pwd)"
LUA="${LUA:-$(command -v lua || command -v lua.exe || command -v lua5.1)}"
FILES=$(grep -E '^[A-Za-z].*\.lua' "$ROOT/AlternativeClassicActionBars.toc" | tr -d '\r')
cd "$ROOT"
luac -p $FILES > "$OUT/syntax.txt" 2>&1 && echo "SYNTAX OK" >> "$OUT/syntax.txt"
"$LUA" "$HERE/load.lua" "$ROOT" > "$OUT/inventory.txt" 2>&1
for f in $FILES; do luac -l -p $f | grep -oE '(GET|SET)GLOBAL.*; [A-Za-z_][A-Za-z0-9_]*' | sed -E 's/^(GET|SET)GLOBAL.*; /\1 /'; done | sort -u > "$OUT/globals.txt"
for f in $FILES; do luac -l -l -p $f | grep -E '^[0-9]+\+? params?, .* upvalues?' | sed -E 's/.*, ([0-9]+) upvalues?.*/\1/' ; done | sort -n | tail -1 > "$OUT/maxupvalues.txt"
grep -q -E '^(LOADERR|RUNERR)' "$OUT/inventory.txt" && echo "LOAD FAILED: $(head -1 "$OUT/inventory.txt")" || echo "load ok ($(wc -l < "$OUT/inventory.txt") inventory entries)"
cat "$OUT/syntax.txt" | tail -1; echo "max upvalues: $(cat "$OUT/maxupvalues.txt")"; echo "globals: $(wc -l < "$OUT/globals.txt")"
