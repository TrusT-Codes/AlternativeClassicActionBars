# CLAUDE.md diet: no-loss table

Every section and bold rule of the old `CLAUDE.md` (33 305 bytes, commit `d16659e`) → where it lives now.
"arch" = `docs/architecture.md`, "skill" = `~/.claude/skills/vanilla-wow-addon/`, "new" = new `CLAUDE.md`.

| Old section / rule | New location |
|---|---|
| `# CLAUDE.md` intro line ("This file provides guidance…") | dropped (boilerplate, no fact) |
| `## Chat output style: "Cavemen Speak"` | new "Style" (short) + arch "Style (full text)" (verbatim) |
| `## Comment style: WHAT, not WHY` (incl. must-stay warning exception) | new "Style" (short) + arch "Style (full text)" (verbatim) |
| `## What this is` | new intro (3 lines) |
| `## Commands` | new "Commands" (short) + arch "Commands (full detail)" (verbatim) |
| **Syntax-check every file you touch** (luac50, hook, lint50, Lua 5.1 for listings) | new "Commands" + arch "Commands" |
| **Verify harness** (outDir outside worktree, `GET` global = lost local) | new "Commands" + arch "Commands" |
| **No build/install command** | new intro + arch "Commands" |
| Runtime testing live; don't guess (pointer) | new intro + new "Lua & client rules" |
| **Release versioning** | new "Commands" (short) + arch "Commands" (verbatim) |
| `## Critical constraint: Lua 5.0, not 5.1+` | new "Lua & client rules" (safety net) + skill `SKILL.md` "Lua 5.0 hard rules" |
| no `...`/`{...}` → `arg`/`unpack(arg)` | new + skill |
| no `#` → `table.getn` | new + skill |
| **No `%` operator at all** | new + skill |
| no hex literals | new + skill |
| no `string.gmatch` → `gfind` | new + skill |
| `select`/`wipe`/`xpcall`/`hooksecurefunc` available; secure-ish APIs unavailable | skill `SKILL.md` + `references/client-facts.md` §3 |
| `string.match` available, Core.lua dispatcher relies on it | arch "Lua 5.0 / client rules: ACAB residue" (verbatim) + skill + `known-problems.md` "Lua / runtime" |
| **Max 32 upvalues per function** | new + skill |
| Closures/metatables/coroutines/`table.*` work, check arg order | arch "ACAB residue" (verbatim) + skill (manual pointer) |
| Ports from 5.1+ (incl. retail Bartender2) must be rewritten | arch "ACAB residue" (verbatim) + skill |
| `## this vs :method() convention` | new "Lua & client rules" + skill `SKILL.md` "Client model" |
| `## No secure-handler system` (`InCombatLockdown` false, `PLAYER_REGEN_*`, plain frames free in combat) | new "Lua & client rules" + skill "Client model" |
| `## Prefer upstream mod APIs over hand-rolled code` | new (one line) + arch "Prefer upstream mod APIs" (verbatim) + skill client-facts §3 |
| **action slots 73–120** (ButtonForge Classic, MIT) | new + arch (verbatim) + skill client-facts §4.2 |
| Mouseover casting, `GetCastInfo`, cooldown/range APIs, `C_Timer`, ClassicAPI reuse list | arch (verbatim) + skill client-facts §3/§4.3 |
| **Caveat:** `PixelUtil.SetPoint` on FontString/Texture → `ACAB:PixelSetPoint` | new (one line) + arch (verbatim) + skill patterns "PixelUtil wrapper" |
| `bit` source | arch (verbatim) + skill client-facts §2 |
| `## Verifying uncertain client behavior` | new "Lua & client rules" (short) + arch "Verifying uncertain client behavior" (verbatim) + skill "Verifying uncertain behavior" |
| **Keep every `/run` ≤ 250 chars** | new + arch + skill |
| `/acab diagN` in Core.lua dispatcher, trace buffer + build tag | new (short) + arch (verbatim) |
| **Remove diagnostics once confirmed** | new + arch + skill |
| No "just in case" code paths; env §4 holds results; MISTAKES cautionary case | new + arch (verbatim) |
| `## Architecture` intro (global table, `ACABDB`/`ACABProfilesDB`/`ACABCharDB`, `EnsureDB`, sanitizer, `.toc` order) | new "Core rules" + arch "Architecture" (verbatim) |
| File list 1–29 (full descriptions incl. slash commands, profile system, wizard, `RunLoginSequence`) | new "Files" (one line each) + arch "Architecture" (verbatim) |
| **Must load before `DefaultBars.lua` and `NativeElements.lua`** (ElementEngine) | new "Files" #6 + arch |
| DefaultBars top-level `InstallReanchorGuard` | new "Files" #7 + arch |
| NativeElements top-level guard calls | new "Files" #8 + arch |
| **Owns the real action-slot pool allocator** (Bar.lua), bar IDs not indices, saved config keys | new "Files" #13 (allocator) + arch |
| Dialog.lua defines `ACABDialogMixin` at load | new "Files" #21 + arch |
| SetupWizard loads before Settings, runtime-only calls; **inside the settings window**, **real settings page** | new "Files" #22 + arch |
| Settings.lua inits `ACAB.simpleBarPageConfigs` | new "Files" #23 + arch |
| **Must load after `Settings.lua`** (SettingsBars, SettingsSimplePages) | new "Files" #24/#26 + arch |
| Events.lua loads **last**; **Nothing may do addon work before login** (`loginSequenceDone`) | new "Files" #28 + new "Core rules" + arch + `known-problems.md` "Other must-stay spots" |
| HoverBind `bindings.xml` route, `SetBindingClick`/`BONUSACTIONBUTTON` dead ends, redirect | new "Files" #17 (short) + arch |
| **Canonical positions** (CENTER/visualCenter, insets, `GetUIParentAnchorSize`, shape/scale before position, partial writers) | new "Core rules" (one line) + arch (verbatim) |
| `Mixin()` **direct table copy**, capture **before** Mixin | new "Core rules" + arch (verbatim) + `known-problems.md` "Capture before Mixin" |
| Same-name `CreateFrame` makes a **brand new** frame; `DropDownList1` **single shared global** | new "Core rules" + arch (verbatim) + skill "Client model" |
| `## Research doc` (env doc authority, §3/§4/§5, `env §N`, parked DLL plan) | new "Docs" + arch "Docs" (verbatim) |
| **`docs/known-problems.md`** | new "Docs" + arch "Docs" (verbatim) |
| **`docs/release-checklist.md`** | new "Docs" + arch "Docs" (verbatim) |
| **`MISTAKES.md`** (entry per new mistake) | new "Docs" + arch "Docs" (verbatim) |
| `## Type definitions repo (local reference)` (clone URL, commit `72ab041`, **GPLv3**, FrameXML, d.lua **unverified**, **nothing** for the mods, trust order, `.luarc.json`) | new "Docs" (one line) + arch "Type definitions repo" (verbatim) |

New rules added (not in the old file): navigation rules, `docs/symbols.txt`, `scripts/docs-for.sh`, `Files:` lines on every known-problems/MISTAKES entry, brief template, stage-by-exact-path in Commands.
