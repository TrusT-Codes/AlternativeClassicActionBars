# Environment Capability Analysis (ACAB residue)

**Client facts are canonical in the `vanilla-wow-addon` skill: `~/.claude/skills/vanilla-wow-addon/references/client-facts.md`.** It uses the same § numbers as this file, so `env §N` means that skill section plus the ACAB-specific notes here. Every §4 fact there was live-confirmed while building ACAB.

This file keeps only what is ACAB-specific: where the code relies on a fact, ACAB's own names, and the raw live examples.

- A new client fact goes into the skill's `client-facts.md` (§4, or §5 while unconfirmed); ACAB-only detail goes here under the same §.
- Where a quirk bites *this codebase* (file + function), see `docs/known-problems.md`.
- How past mistakes happened and how to avoid repeating them, see `MISTAKES.md`.

---

## 1. Sources and confidence
Nothing ACAB-specific.

## 2. Lua 5.0 runtime
House rules: `CLAUDE.md` ("Lua & client rules") and the skill's `SKILL.md`.

## 3. Client mods: what to reuse
- `PixelUtil.SetPoint` on FontString/Texture: ACAB goes through `ACAB:PixelSetPoint` (`ElementEngine.lua`).
- Action-bar framework, grid layout, action-slot constants and Blizzard-art hiding are built by ACAB itself; none of the mods provide them.

## 4. Live-confirmed client behavior

### 4.1 Security and combat
Nothing ACAB-specific.

### 4.2 Action slots and buttons
- ACAB reserves 12 slots per custom bar out of the 48, so there is a hard maximum of 4 custom (Extra) bars. `ButtonForge Classic` (MIT) was read in full during research; the security boundary is the native action-slot system itself.

### 4.3 Casting and cooldown data
- `SPELL_START_SELF/OTHER` arg 1 example: Small Bronze Bomb → 4374. Arg 6 (cast duration ms) matches `C_Spell`.
- Live: First Aid fired `UNIT_SPELLCAST_CHANNEL_START` with `arg1 = "player"`.
- Because `SPELL_START/GO_SELF` need nampower CVars, ACAB's glow uses `IsCurrentAction` (macro slots: see `known-problems.md` "Macro slots use our own parser").

### 4.4 Keybinding
- `aBindings/` in this repo is the `bindings.xml` reference (not ours, don't modify).
- ACAB ships `ACABBIND1-48`, `ACABPETBIND1-10`, `ACABSTANCEBIND1-10` and `ACABEDITMODEESCAPE`. Edit mode's Escape uses a temporary `ESCAPE` → `ACABEDITMODEESCAPE` binding.

### 4.5 Native globals and saved state
- `LOCK_ACTIONBAR` live: writing it mid-session blocked dragging off a native bar without a reload.
- Live: `GetActionBarToggles()` returned `1 1 1 nil` while `SHOW_MULTI_ACTIONBAR_1-4` were all `1` (set by ACAB), and `VIEWABLE_ACTION_BAR_PAGES` still had page 4 viewable.
- ACAB's own saved enable flag is authoritative and is pushed into the client every login.
- `ACABDB` is account-wide, so one-shot markers can't force a watched recapture: use `/acab recapture`.
- A channel left before `/reload` was still at `GetChannelName` 0 after 15 s (update-check channel opt-out).
- Installed folder name: `Interface\AddOns\AlternativeClassicActionBars\...`.

### 4.6 Frame rects and coordinates
- The load-bearing ancestor-first resolve pass: `Settings.lua` `ApplySettingsHeightFromCandidates`.
- Screen size: `ACAB:GetUIParentAnchorSize` (CENTER-anchored probe).

### 4.7 Frame identity
- Pooled named frames: `SettingsBars.lua` `RebuildDefaultBarAssignmentRows` / `RefreshBarList` (see `known-problems.md` "Same-name `CreateFrame` makes a second frame").

### 4.8 Strata and frame level
- ACAB pins the art frame to LOW level 5; bars, buttons, cooldowns, chain containers, Key Ring and Page Indicator sit at LOW level 10+, reasserted on every apply. `MainMenuBar` gets `EnableMouse(false)`.
- Every edit-mode overlay is parented to `UIParent` so levels compare in one tree.

### 4.9 Login timing
- `MainMenuBar` re-center: a ~76 px shift in `ActionButton1:GetLeft()`. Capture waits in `Core.lua` `WaitForNativeBarSettle`.
- Native re-anchors: handled by `ElementEngine.lua` `InstallReanchorGuard` plus a `PLAYER_REGEN_ENABLED` reassert. The 1.3.0-rc2 logged session (25 `LOOT_CLOSED`, 17 `PLAYER_REGEN_ENABLED`, nothing moved) is why the `LOOT_CLOSED` reassert was dropped.

### 4.10 Native Main Bar elements
Nothing ACAB-specific (code locations: `known-problems.md` "Native frames and FrameXML").

### 4.11 Pet Bar
Nothing ACAB-specific.

### 4.12 Stance / shapeshift
- `UPDATE_SHAPESHIFT_FORMS` on learning: fired twice on a rogue learning Stealth.
- Zoning count growth (live, warrior entering a dungeon: `GetNumShapeshiftForms()` 1, 2, 3 at the same `GetTime()`): ACAB waits a frame in `Events.lua` `ApplyPendingStanceLiveShape`.
- Active icon swap, live: Aspect of the Monkey/Hawk → `Spell_Nature_WispSplode`, Stealth → `Spell_Nature_Invisibilty`.

### 4.13 Experience Bar
- `UnitXP`, `UnitXPMax`, `GetXPExhaustion`, `IsResting`, `GetRestState` behave as in `BEB/` (the reference addon).
- Rested pool live: a kill giving 31 rested bonus XP dropped `GetXPExhaustion()` by 46.5. ACAB measures the ratio on each character's first rested kill (`ExperienceBar.lua` `GetRestedBonusXP`, `ACABCharDB.restPoolPerBonusXP`).
- `ACAB.XP_PER_LEVEL` matches the Turtle table (level 11 → 8800).
- Border art: `UI-MainMenuBar-Dwarf` is one race atlas example; the bar's bottom 3 units have no art, and ACAB's gradient strip is final.

## 5. Open questions (unconfirmed)
Kept in the skill's `client-facts.md` §5.
