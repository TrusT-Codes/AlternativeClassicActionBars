#!/usr/bin/env bash
# Prints every docs/known-problems.md and MISTAKES.md entry whose "Files:" line
# names one of the given files (basename match); with --general, also "Files: *" entries.
# Inside a matched entry, a top-level bullet tagged "<!-- Files: ... -->" prints only if it matches too.
# Usage: scripts/docs-for.sh [--general] Button.lua [Core.lua ...]   (--general adds "*" entries)
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
general=0
args=""
for a in "$@"; do
  if [ "$a" = "--general" ]; then general=1; else args="$args $(basename "$a")"; fi
done
if [ -z "$args" ]; then
  echo "usage: $0 [--general] <File.lua> [File.lua ...]" >&2
  exit 1
fi

for doc in docs/known-problems.md MISTAKES.md; do
  awk -v want="$args" -v general="$general" -v doc="$doc" '
    BEGIN { n = split(want, w, " "); for (i = 1; i <= n; i++) wanted[w[i]] = 1 }
    function matches(list,   m, i, f) {
      if (list == "*") return general
      m = split(list, f, /, */)
      for (i = 1; i <= m; i++) if (f[i] in wanted) return 1
      return 0
    }
    function endchunk() { if (chunkkeep) body = body chunk; chunk = ""; chunkkeep = 1 }
    function flush() {
      endchunk()
      if (head != "" && keep) printf "=== %s: %s\n%s\n", doc, head, body
      head = ""; body = ""; keep = 0
    }
    { sub(/\r$/, "") }
    /^##+ / { flush(); head = $0; sub(/^#+ /, "", head); next }
    /^---$/ { flush(); next }
    head == "" { next }
    /^Files: / { keep = matches(substr($0, 8)); next }
    /^- / {
      endchunk()
      if (match($0, /<!-- Files: [^>]* -->/)) {
        chunkkeep = matches(substr($0, RSTART + 12, RLENGTH - 16))
        $0 = substr($0, 1, RSTART - 2)
      }
    }
    /^$/ { endchunk() }
    { chunk = chunk $0 "\n" }
    END { flush() }
  ' "$root/$doc"
done
