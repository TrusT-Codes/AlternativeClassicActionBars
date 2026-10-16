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
- `scripts/docs-for.sh <files you touch>`: before editing. Prints the `known-problems.md` + `MISTAKES.md` entries for those files (`--no-general` skips `Files: *`). Don't read the two docs whole.
- `docs/known-problems.md`: quirks, must-stay orderings, tech debt. Code cites it as `see known-problems.md: "<title>"`; put findings there, not in WHY comments.
- `MISTAKES.md`: solved mistakes (what / root cause / prevention). Add an entry for every new mistake.
- **Every new entry in either doc gets a `Files: A.lua, B.lua` line under its heading (`Files: *` if general).**
- `docs/architecture.md`: full per-file descriptions, SavedVariables/profiles, canonical positions, Mixin capture order, same-name `CreateFrame`, slash commands, tooling detail, type-defs repo.
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

## Files (`.toc` order; detail in `docs/architecture.md`)
Top-level (file-load-time) calls may only use earlier files; runtime calls go anywhere. New file: `.toc` + this list.
1. `Core.lua` — ids/constants, snap, edit/hoverbind modes, fade, login sequence, `/acab` slash dispatch
2. `UpdateCheck.lua` — version compare, peer version broadcast over addon messages + hidden channel
3. `Database.lua` — SavedVariable lifecycle, `EnsureDB`, sanitizer, UI-scale check, profile system
4. `ProfileIO.lua` — profile export/import (`TBVPROFILE1:`, hand-rolled parser). Runtime only
5. `ProfileDialogs.lua` — create-profile + first-login dialogs. Runtime only
6. `ElementEngine.lua` — element engine; **load before DefaultBars/NativeElements** (top-level guards)
7. `DefaultBars.lua` — Main Bar paging/art, bars 1–5, Modern geometry; top-level `InstallReanchorGuard`
8. `NativeElements.lua` — Bag Bar, Micro Menu, Key Ring, Latency/Cast Bar; top-level guard calls
9. `PageIndicator.lua` — Page Indicator element. No top-level calls
10. `Tooltip.lua` — Tooltip element (`GameTooltip` default-anchor redirect). No top-level calls
11. `PetStanceBars.lua` — native-mode Pet/Stance Bars (cross-call each other's reflows)
12. `ExperienceBar.lua` — Exp Bar position/colors, rested overlay, Better Exp Bar text
13. `Bar.lua` — bar grid engine (custom + default-family bars); owns the slot allocator (pages 7–10)
14. `LayoutGrid.lua` — Edit Layout grid overlay. Runtime only
15. `ExtraBars.lua` — Extra Bars 6–9 policy. Runtime only
16. `Button.lua` — slot-backed pool button; one event dispatcher + range ticker; slot changes via `Rebind`
17. `HoverBind.lua` — hoverbind mode, custom slots via `bindings.xml`; top-level `customBindTargets = {}`
18. `Minimap.lua` — minimap launcher button
19. `Menu.lua` — minimap right-click menu (native `UIDropDownMenuTemplate`)
20. `UIWidgets.lua` — Mixin widget kit: modern buttons, sliders, list rows, `ACAB.*_BACKDROP` tables
21. `Dialog.lua` — `ACABDialogMixin` (global at load) + `ACAB:ShowDialog`
22. `SetupWizard.lua` — setup wizard inside the settings window; calls settings files at runtime only
23. `Settings.lua` — settings shell, height-fit, gating; inits `ACAB.simpleBarPageConfigs = {}`
24. `SettingsBars.lua` — bar pages, shared page helpers, bar list. **Must load after Settings.lua**
25. `ForceVanillaLayout.lua` — Force Vanilla Layout Mode toggle + reset. Runtime only
26. `SettingsSimplePages.lua` — native-element pages. **After Settings.lua** (top-level fill), SettingsBars
27. `SettingsGeneral.lua` — General/Profiles/Edit Mode tabs, `WIDE_VIEWS`, Export/Import/Copy dialogs
28. `Events.lua` — addon-wide event frames. **Loads last** among `.lua` files (handlers call every file)
29. `bindings.xml` — `ACABBIND1-48` / `ACABPETBIND1-10` / `ACABSTANCEBIND1-10` binding actions
