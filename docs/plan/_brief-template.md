# Brief: <title>

Copy this skeleton for a new orchestrator/agent brief. Delete the hints in `<…>`.

## Goal
<One or two sentences: the user-visible outcome.>

## Scope
- Files in scope: `<A.lua>`, `<B.lua>`
- Out of scope: <what must not change>
- Branch: `<type>/<name>` from `origin/<release branch>`. Small commits, don't push, stage by exact path.

## Read first (nothing else whole)
- `bash scripts/docs-for.sh <files in scope>` — every entry it prints.
- `env §<N.N>` (<why>): skill `references/client-facts.md` + `docs/01-Environment-Capability-Analysis.md` residue, that section only.
- Symbols: grep `docs/symbols.txt` for `<Name>`; Read code with `offset`/`limit` around hits.
- `docs/architecture.md` section(s): <"Architecture" entry for X.lua / "Canonical positions" / …>, only if needed.

## Steps
1. <step> — done when <check>.
2. <step> — done when <check>.

## Verify
- `luac50 -p` on every touched file (hook does it too).
- `bash scripts/verify/verify.sh "$PWD" <outDir outside the worktree>` — no new `GET` globals.
- Live checks for the user: <`/run` ≤ 250 chars, with the output that confirms each hypothesis> or `docs/release-checklist.md` rows <…>.

## Report (≤ 20 lines, Cavemen Speak)
- Files changed (path + one line).
- Verify result.
- Open questions / decisions for the user.
- Doc text to add (`known-problems.md` / `MISTAKES.md` entries with a `Files:` line, env §4 facts).
- No full diffs, no file dumps.
