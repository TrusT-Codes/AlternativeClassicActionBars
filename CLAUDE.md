# CLAUDE.md

ACAB (`AlternativeClassicActionBars`): Bartender2-style action bar addon for a modded WoW 1.12.1 client (Turtle base + SuperWoW, nampower, ClassicAPI, UnitXP_SP3). Lua 5.0. No build, no package manager, no tests: the client loads `AlternativeClassicActionBars.toc` directly; runtime testing is live, in the user's client.

## Style
- **Chat: Cavemen Speak.** Short broken sentences, small words, no filler, hedging or recap ("Fixed. Edge case handled now."). Code, diffs, paths, identifiers stay exact.
- **Comments: WHAT, not WHY.** One short line, no rationale or debugging history. Only exception: a short must-stay warning (`-- must run before X or the cooldown desync bug returns`). Rationale goes to `docs/known-problems.md`.

## Lua & client rules
**Load the `vanilla-wow-addon` skill before writing or reviewing Lua.** Safety net (full lists in the skill):
- Lua 5.0: no `#` (`table.getn`), no `%` (`n - math.floor(n/d)*d`), no `...` expressions (`arg`, `arg.n`, `unpack(arg)`), no `gmatch` (`gfind`), no hex literals, max 32 upvalues per function.
- Script handlers get globals `this`/`event`/`arg1`…, not `self`/params; only `:method()` calls get `self`.
- No secure system (`SecureActionButtonTemplate`/`SecureHandler*`). `InCombatLockdown()` always returns false: never gate on it; combat = `PLAYER_REGEN_*`.
- Never guess client behavior: grep `wow-api-type-definitions/UI_Turtle/FrameXML/`, else hand the user a `/run` (≤ 250 chars incl. `/run `, full global name) and wait. No "just in case" fallbacks. Bigger checks: temporary `/acab diagN`, removed once confirmed.
- Prefer mod APIs: `C_Timer` (never OnUpdate polls), `Mixin`, `PixelUtil` via `ACAB:PixelSetPoint`. Custom buttons use action slots 73–120.

## Commands
- `luac50 -p <File>.lua` on every touched file. The global PostToolUse hook runs luac50 + lint50 after each `.toc`-listed `.lua` edit; a hook error means fix first.
- `bash scripts/verify/verify.sh "$PWD" <outDir>` (outDir outside the worktree, e.g. main checkout's `.git/acab-verify/`): luac50, lint50, stub-load in `.toc` order, globals, upvalues; regenerates `docs/symbols.txt`. A new `GET` global = lost local.
- Release: `scripts/Build-Release.ps1` stamps `## Version:` from the `v*` tag; still bump the committed `.toc` `## Version:` by hand after each release.
- Git: stage by exact path; the user keeps untracked notes in `docs/plan/`.

## Navigation
- Find a symbol with Grep (`function ACAB[:.]Name`), then Read with `offset`/`limit` around it.
- Never Read a whole file over ~800 lines unless the task edits most of it.
- Before writing a helper, grep `docs/symbols.txt` for an existing one. It's generated (`scripts/symbols.sh`, run by `verify.sh`): grep only, never read whole, never edit.

## Docs (when to read)
- `scripts/docs-for.sh <files you touch>`: before editing. Prints the `known-problems.md` + `MISTAKES.md` entries for those files (`--general` adds `Files: *` entries; their rules are condensed in "Process rules"). Don't read the two docs whole.
- `docs/known-problems.md`: quirks, must-stay orderings, tech debt. Code cites it as `see known-problems.md: "<title>"`; put findings there, not in WHY comments.
- `MISTAKES.md`: solved mistakes (what / root cause / prevention). Add an entry for every new mistake.
- **Every new entry in either doc gets a `Files: A.lua, B.lua` line under its heading (`Files: *` if general).**
- `docs/architecture.md`: file index + full per-file descriptions, SavedVariables/profiles, canonical positions, Mixin capture order, same-name `CreateFrame`, slash commands, tooling detail, type-defs repo.
- `env §N` = skill `references/client-facts.md` §N (canonical client/mod facts: §3 reuse, §4 confirmed, §5 open) + ACAB residue in `docs/01-Environment-Capability-Analysis.md` §N. Read the named section only. New facts: generic → skill, ACAB-only → env doc.
- `docs/release-checklist.md`: in-game test matrix for every release candidate.
- `wow-api-type-definitions/`: gitignored GPLv3 clone, grep only, never copy. Trust: client-facts/env §4 > `UI_Turtle` FrameXML > `Client/*.d.lua` > general knowledge.
- New briefs start from `docs/plan/_brief-template.md`.

## Core rules
- Global `AlternativeClassicActionBars` (file-local alias `ACAB`; `/run` needs the full name). SavedVariables: `ACABDB` (account), `ACABProfilesDB`, `ACABCharDB` (per character).
- New persisted field: default in `ACAB:EnsureDB()` (append only), crash-prone types into `ACAB:SanitizeProfileData`'s key lists.
- Positions are canonical `CENTER`/`CENTER` visual-center offsets in UIParent units; apply shape/scale before position in resets.
- Capture native methods before `Mixin()`. `CreateFrame` with an existing name makes a second frame: create named frames once.
- No addon work before login: pre-login handlers/hooks return early until `ACAB.loginSequenceDone` (or `ACAB.activeProfileName`).

## Load order (`.toc`; file index + detail in `docs/architecture.md`)
Top-level (file-load-time) calls may only use earlier files; runtime calls go anywhere. New file: `.toc` + `architecture.md`.
- `ElementEngine.lua` loads before `DefaultBars.lua` / `NativeElements.lua` (their top-level guard calls).
- `HoverBind.lua`'s top-level `customBindTargets = {}` runs before any button is created.
- `Dialog.lua` defines the `ACABDialogMixin` global at load.
- `Settings.lua` (inits `ACAB.simpleBarPageConfigs = {}`) loads before `SettingsBars.lua` and `SettingsSimplePages.lua` (top-level fill).
- `SetupWizard.lua` loads before `Settings.lua`; calls settings files at runtime only.
- `Events.lua` loads last among `.lua` files; `bindings.xml` declares `ACABBIND*`/`ACABPETBIND*`/`ACABSTANCEBIND*`.

## Process rules (condensed `Files: *` entries; `docs-for.sh --general` prints the originals)
- Live state beats code reading or retail memory: hand the user a `/run` first, not an agent. A guard that hides a wrong guess is not verification.
- Binary string finds and retail designs are hypotheses until env §3/§4 or a live `type(x)` confirms them.
- `/run` checks: set and restore `this`/`event` around native handler calls; ask which run a result came from.
- Removing "debug-only" code changes behavior → restore it byte for byte, bisect one variable at a time.
- One fix doesn't close a bug: re-run the original live check. Visual mismatch: compare with the addon disabled first.
- Diagnostic traces: label every candidate entry point; first line is a build tag.
- Code with backslashes: Edit/Write tools only, never a shell heredoc; grep texture paths after scripted edits.
- Before switching branches: `git show --stat`.
