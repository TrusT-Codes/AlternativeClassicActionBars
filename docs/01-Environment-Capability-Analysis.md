# Environment Capability Analysis

What the runtime (vanilla 1.12.1 client, Lua 5.0, SuperWoW, nampower, ClassicAPI, UnitXP_SP3) can and cannot do, as confirmed for this addon. **§4 is ground truth**: every entry there was live-confirmed on the real client unless it says otherwise. Prefer it over retail or general WoW addon knowledge, which often does not apply here.

- Where a quirk bites *this codebase* (file + function), see `docs/known-problems.md`.
- How past mistakes happened and how to avoid repeating them, see `MISTAKES.md`.
- Still-open questions are collected in §5. Move an item into §4 once it is confirmed live.

---

## 1. Sources and confidence

- **ClassicAPI** ships its whole Lua source embedded in the DLL, so what §3 says about it was read from the real source.
- **SuperWoW** and **nampower** were read via string extraction from the binaries, plus nampower's published `SCRIPTS.md`.
- **UnitXP_SP3** is UPX-packed with a broken header. Its entry is based on the maintainer's docs only, so it is the least certain.
- **String tables mislead.** A list of names in a binary is not proof that each one is a registered global. See §4.1: several taint functions were listed but are `nil` live.

---

## 2. Lua 5.0 runtime

The house rules are in `CLAUDE.md` ("Critical constraint: Lua 5.0"). Extra detail:

- `unpack(t)` stops at the first `nil` hole unless `t.n` is set. Forward varargs with `unpack(arg)`, since `arg` carries `.n`.
- `X and X(...)` keeps only the **first** return value (plain Lua semantics). To capture several returns behind an existence guard, use a real `if X then ... end` block.
- `math.sin`, `math.pi` and the rest of the standard math library are present.
- `GetCVar("unknownName")` throws a hard error, it does not return `nil`. Never probe CVar names by guessing.
- **`hooksecurefunc(table, "Method", fn)` works** (per-instance form, live: original then hook both ran), not only the global-name form.

---

## 3. Client mods: what to reuse

| Need | Source | Status |
|---|---|---|
| Scheduling (tickers, one-shots, debounce) | ClassicAPI DLL-native `C_Timer.After` / `NewTimer` / `NewTicker` (handles have `:Cancel()`); `TimedCallbackMixin` for restart-on-call debounce | **Reuse.** Never hand-roll an `OnUpdate` poll |
| Pixel-perfect anchoring/sizing | ClassicAPI `PixelUtil` (verbatim retail port, uses DLL-native `GetPhysicalScreenSize()`) | **Reuse.** `PixelUtil.SetPoint` crashes on FontString/Texture arguments (no `GetEffectiveScale`); go through `ACAB:PixelSetPoint` |
| OOP for bars/buttons/widgets | ClassicAPI `Mixin` / `CreateFromMixins` (DLL-native) + `CreateAndInitFromMixin` | **Reuse.** `Mixin` copies functions onto the instance; capture native methods first |
| Table/math/geometry helpers | ClassicAPI `TableUtil`, `MathUtil`, `Rectangle`, `Vector2D` | **Reuse** |
| Internal pub/sub | ClassicAPI `CallbackRegistryMixin` / `EventRegistry` | **Reuse** |
| Frame/texture pools | ClassicAPI `CreateUnsecuredFramePool` & co. | **Reuse** |
| Slash commands | ClassicAPI `RegisterNewSlashCommand` | **Reuse** |
| `HookScript` on frames | ClassicAPI | **Available** |
| `hooksecurefunc`, `select`, `wipe`, `xpcall`, `string.match` | ClassicAPI (source of `string.match` unconfirmed) | **Available.** Only the 2-arg global form `hooksecurefunc("Name", fn)` is confirmed |
| Bit operations | Global `bit` (`band`/`rshift`/`lshift`) | **Available**, most likely from the Turtle WoW base client. Re-check on a non-Turtle server |
| Cooldowns | nampower `GetSpellIdCooldown` / `GetItemIdCooldown` / `GetTrinketCooldown` (reusable table: `isOnCooldown`, `cooldownRemainingMs`, per-category blocks) | **Reuse** |
| Range/usability | nampower `IsSpellInRange` / `IsSpellUsable` | **Reuse** |
| Icons/metadata | nampower `GetSpellIconTexture`, `GetItemIconTexture`, `GetSpellRec(Field)`, `GetSpellNameAndRankForId` | **Reuse** |
| Player cast bar + GCD | nampower `GetCastInfo()` (one table: `spellId`, `castType`, `castStartS`/`castEndS`, `castRemainingMs`, `gcdEndS`/`gcdRemainingMs`) | **Reuse. Only option** for the player (§4.3) |
| Other units' cast bars | ClassicAPI `C_Spell.UnitCastingInfo(unit)` / `UnitChannelInfo(unit)` + `UNIT_SPELLCAST_*` events | **Reuse for non-player units only** (§4.3) |
| Queue/cast events | nampower `SPELL_QUEUE_EVENT`, `SPELL_CAST_EVENT`, `SPELL_START/GO/FAILED_SELF/OTHER`, `SPELL_CHANNEL_START/UPDATE` | **Available**, args in §4.3 |
| Mouseover casting | SuperWoW `CastSpellByName(name, "mouseover")` from the button's `OnClick`, bypassing `UseAction` for that button | **Reuse** (§4.2) |
| Action-bar framework, grid layout, action-slot constants, Blizzard-art hiding | — | **Build ourselves.** None of the mods provide any of it |
| Timer independent of the frame loop | UnitXP `UnitXP("timer", "arm", ...)` | Fallback only; `C_Timer` covers every need |

Other mod features, noted but not used: SuperWoW `UnitPosition`, `TrackUnit`, `SpellInfo`, `ImportFile`/`ExportFile`, `UNIT_CASTEVENT`/`RAW_COMBATLOG`; nampower aura/equipment/unit-field functions and its `CustomData` file IO; UnitXP line-of-sight/distance/facing/targeting helpers. ClassicAPI's `UIParent.lua` holds only `MouseIsOver()`, and its `Constants.lua` holds only item/character-sheet constants. Neither has layout or action-bar constants.

---

## 4. Live-confirmed client behavior

### 4.1 Security and combat
- **No secure-handler system.** `CreateFrame` with any `SecureHandler*Template` or `SecureActionButtonTemplate` fails with "Couldn't find inherited node". That whole system arrived in 2.0.
- **No taint introspection.** `issecurevalue`, `issecurevariable`, `scrubsecurecall`, `securecallfunction`, `secureexecuterange` and `pcallwithenv` are `nil`, even though they appear in ClassicAPI's string table.
- **`InCombatLockdown()` always returns `false`**, even inside real combat. Never gate on it.
- **`SetPoint`/`SetSize`/`SetWidth`/`SetHeight` on plain frames work unrestricted in real combat**, as tested between genuine `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED` events. If combat state is ever needed, use those two events.

### 4.2 Action slots and buttons
- **Custom buttons are plain `CreateFrame("Button")` frames backed by action slots 73–120** (pages 7–10, never used by the stock UI). They are driven through `UseAction`, `PlaceAction`, `PickupAction`, `HasAction`, `GetActionTexture`, `GetActionCount`, `IsActionInRange`, `IsUsableAction` and `GetActionCooldown` + `CooldownFrameTemplate`. This is the `ButtonForge Classic` pattern (MIT). The security boundary is the native action-slot system itself.
- **48 slots, 12 reserved per custom bar**, so there is a hard maximum of 4 custom bars. Default bars 1–5 use native slots outside 73–120.
- **Mouseover:** after SuperWoW's `SetMouseoverUnit(guid)`, native `UnitExists("mouseover")` / `UnitGUID("mouseover")` and nampower's `GetUnitGUID("mouseover")` all agree, so SuperWoW and nampower don't conflict. `UNIT_SPELLCAST_SUCCEEDED` also fires for `mouseover`. Stock 1.12 has no `[target=mouseover]` macro syntax.
- **Native button art:** `ActionButton1Icon` is anchored flush `TOPLEFT` (0, 0), with no inset. `ActionButton1:GetNormalTexture()` is anchored `CENTER` to the button at (0, −1).
- **Native empty-slot rule:** `ALWAYS_SHOW_MULTIBARS` and grid show/hide only affect the multi-bars (bars 2–5). The native Main Bar never hides an empty button.
- The slight bottom/left misalignment between a native `ActionButton` border and the bar art is Blizzard's own. It is not an addon bug.

### 4.3 Casting and cooldown data
- **`C_Spell.UnitCastingInfo(unit)`** returns `name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID`. It works for `"target"`. **For `"player"` it returns all `nil`, even mid-cast.**
- **nampower event arguments** (from real captures; "?" means the meaning is not confirmed):

| Event | Args |
|---|---|
| `SPELL_START_SELF/OTHER` | 1=0?, 2=spellId, 3=caster GUID, 4=target GUID (`0x0…0` if none), 5=cast type? (2 magic, 34 ranged), **6=cast duration ms** (matches `C_Spell`), 7=0?, 8=0 or 2? |
| `SPELL_GO_SELF/OTHER` | 1=0?, 2=spellId, 3=caster GUID, 4=target GUID, 5=hit flags? (256/288), 6=success? (1; 0 with 7=1 on a likely miss), 7 |
| `SPELL_FAILED_SELF` | 1=spellId, 2=reason code? (35, 77), 3=0/1 flag |
| `SPELL_FAILED_OTHER` | 1=caster GUID, 2=spellId |
| `SPELL_CAST_EVENT` | 1=0/1 (queued?), 2=spellId, 3=2, 4=short hex id (not a GUID), 5=0 |
- **`SPELL_CAST_EVENT` fires for instant spells** (Arcane Shot, Serpent Sting) as well as Auto Shot, with `arg2` = spell id; SuperWoW `SpellInfo(arg2)` returns the spell name. `IsCurrentAction(slot)` on a macro slot returns `true` or `1` (both seen) and stays true while a `/cast Auto Shot` in the same macro is active.

### 4.4 Keybinding
- **`SetBindingClick` / `SetBinding(key, "CLICK frame:button")` and `SetBinding(key, "BONUSACTIONBUTTON1")` are dead ends.** They get recorded (`GetBindingAction` and `bindings-cache.wtf` show them) but never fire.
- **What works:** binding names declared in a shipped `bindings.xml` (`<Binding name="X">lua</Binding>`), then `SetBinding(key, "X")`. The file loads once at addon load, so it can't be generated at runtime. `aBindings/` in this repo is the reference (not ours, don't modify). ACAB ships `ACABBIND1-48`, `ACABPETBIND1-10`, `ACABSTANCEBIND1-10` and `ACABEDITMODEESCAPE`.
- An `EnableKeyboard(true)` capture frame blocks every other key on this client. Edit mode's Escape therefore uses a temporary `ESCAPE` → `ACABEDITMODEESCAPE` binding.

### 4.5 Native globals and saved state
- **Lock Action Bars is the plain global `LOCK_ACTIONBAR`**, the string `"1"`/`"0"`. It is not a CVar, and it persists in the WTF `SavedVariables.lua`. Writing it mid-session takes effect at once (live: dragging off a native bar blocked without a reload).
- **Main Bar paging reads `VIEWABLE_ACTION_BAR_PAGES`, which follows Blizzard's saved toggles, not the session globals.** Live: `GetActionBarToggles()` returned `1 1 1 nil` while `SHOW_MULTI_ACTIONBAR_1-4` were all `1` (set by ACAB), and `VIEWABLE_ACTION_BAR_PAGES` still had page 4 viewable.
- **`SHOW_MULTI_ACTIONBAR_1-4` do not persist across logout** on this fork (they are absent from WTF). They are fine for same-session reads, but never treat them as the source of truth at login. The addon's own saved flag is authoritative, and it gets pushed into the client every login.
- **`ACABDB` is account-wide.** Any login or `/reload` on any character consumes a one-shot migration marker. That's fine for migrations, but useless for "force one recapture I can watch". Use an explicit command for that (`/acab recapture`).
- The in-game AddOns folder name is `AlternativeClassicActionBars`, so texture paths must use `Interface\AddOns\AlternativeClassicActionBars\...`. A wrong segment renders blank with no error.

### 4.6 Frame rects and coordinates
- **Rects resolve lazily and top-down.** `GetTop`/`GetBottom`/`GetLeft` are resolved on demand against the anchor's *currently cached* rect, and then cached. `SetVerticalScroll` (and any move of a subtree) doesn't re-resolve children. Reading a child before its stale ancestor caches a wrong value, and that wrong value stays stable on re-reads. Fix: read the ancestor first, then the children, as a discarded, load-bearing resolve pass (`Settings.lua` `ApplySettingsHeightFromCandidates`). Ruled out as causes: same-tick re-reads, one deferred frame, elapsed time, chat output, GC, `GetName`/`IsShown`.
- **No rect until sized.** A frame that has only `SetPoint` returns `nil` from `GetLeft` etc. forever. It resolves as soon as `SetWidth`/`SetHeight` has been called once. Give containers a placeholder `SetWidth(1)`/`SetHeight(1)` at creation.
- **Units.** `GetLeft()`/`GetTop()` are in the queried frame's own effective-scale units. Convert between frames with `value * frame:GetEffectiveScale() / target:GetEffectiveScale()`. `SetPoint` offsets are in the positioned frame's units. `GetWidth()`/`GetHeight()` are local units, and they only match numerically across frames with the same ancestor chain: a UIParent child with `SetAllPoints(MainMenuExpBar)` reported 0.9× the bar's size while aligning visually. Parent a tracking overlay *into* the tracked frame if its size will be read.
- **Screen size:** use `ACAB:GetUIParentAnchorSize` (CENTER-anchored probe). `UIParent:GetWidth()`/`GetHeight()` come out too small.

### 4.7 Frame identity
- **`CreateFrame` with a name already in use creates a second frame** sharing that name (different `tostring()` identity). It does not return the existing one. Native `UIDropDownMenu_*` code resolves sub-widgets via `getglobal(name .. "Text")` etc., so same-named frames corrupt each other, and hiding the old one doesn't help. Give every rebuild unique names (a counter suffix).
- `DropDownList1` is one shared global popout, not per instance.

### 4.8 Strata and frame level
- **Strata always beats level.** Order: `BACKGROUND < LOW < MEDIUM < HIGH < DIALOG < FULLSCREEN < FULLSCREEN_DIALOG < TOOLTIP`.
- **Racing a native frame's level inside the same strata is fragile.** `MainMenuBarArtFrame` raises its own level on click (`:Raise()`) and buries siblings at its strata. ACAB pins the art frame to LOW level 5 and puts bars, buttons, cooldowns, chain containers, Key Ring and Page Indicator at LOW level 10+, reasserted on every apply. That keeps them under open bags (MEDIUM). `MainMenuBar` (MEDIUM, mouse-enabled) gets `EnableMouse(false)`, or it swallows clicks meant for the LOW bars.
- **A `CooldownFrameTemplate` child defaults to MEDIUM.** Set it to its button's strata explicitly.
- **Same-strata, same-level overlaps are undefined.** Creation order doesn't settle them, so overlapping overlays need distinct explicit levels. Levels are only comparable within one parent tree, which is why every edit-mode overlay is parented to `UIParent`.
- **Strata survives `SetParent`.** A reparented native button keeps its old strata, so reassert it after reparenting.
- **A new child frame inherits its parent's strata** (live: child of a HIGH frame reported HIGH).

### 4.9 Login timing
- **`MainMenuBar` re-centers horizontally after `PLAYER_LOGIN`** (a ~76 px shift in `ActionButton1:GetLeft()`). Capture native positions only after `PLAYER_ENTERING_WORLD` plus a stability poll (`Core.lua` `WaitForNativeBarSettle`). Two equal reads 0.1 s apart prove local stability only, not finality.
- Native FrameXML re-anchors wrapped frames later on its own (Key Ring, Latency Bar, Micro Menu/Bag Bar buttons, the art frame), without `ClearAllPoints`. Handled by `InstallReanchorGuard`, plus a position reassert on `PLAYER_REGEN_ENABLED` / `LOOT_CLOSED`.

### 4.10 Native Main Bar elements
- `ActionButton1-12` are children of `MainMenuBarArtFrame`. To hide the art, hide only the `Texture` entries of `MainMenuBarArtFrame:GetRegions()` (regions are never child frames), never the frame itself.
- `KeyRingButton` exists (Turtle addition). It is anchored `RIGHT` of `CharacterBag3Slot` (x −5), so reparenting bag buttons doesn't change what it follows.
- `MainMenuBarPerformanceBarFrame` (Latency Bar) is a sibling of `MainMenuBarArtFrame` under `MainMenuBar`, not a child.
- `ActionBarUpButton`, `ActionBarDownButton`, `MainMenuBarPageNumber` exist. The page number is a FontString (no `GetEffectiveScale`).
- `TalentMicroButton` exists but is hidden below level 10. Chain layouts must skip hidden buttons live and re-layout via `hooksecurefunc("UpdateMicroButtons", ...)`.
- `ShapeshiftBar_Update` picks its border art from `MultiBarBottomLeft:IsShown()`.

### 4.11 Pet Bar
- **`GetPetActionInfo(i)` returns 7 values:** `name, subtext, texture, isToken, isActive, autoCastAllowed, autoCastEnabled`. `subtext` is often `nil` but still takes position 2.
- **`isToken`:** `name`/`texture` are global names (e.g. `"PET_ACTION_ATTACK"`, `"PET_ATTACK_TEXTURE"`), so resolve them with `getglobal()`, falling back to the raw string.
- **`GameTooltip:SetPetAction(i)` does not handle token slots.** For those, build the tooltip from `getglobal(name)` (+ `subtext`), like native `PetActionButton_OnEnter`.
- **Autocast shine is a `Model` child**, `PetActionButton<N>AutoCast` (`GetModel()` = `Interface\Buttons\UI-AutoCastButton`, all-points anchored, HIGH strata), shown only while autocast is on. `AutoCastShineFrameTemplate` and `AutoCastShine_*` don't exist, and there is no `AnimationGroup` system. Calling `SetModel()` again on a reparented one turns it into a white plane; resize it with `SetModelScale`. Before hand-rolling an animated effect, look for an existing native `Model` child and reuse its model path.

### 4.12 Stance / shapeshift
- `GetShapeshiftFormInfo(i)` returns `texture, name, isActive, isCastable`. `GetShapeshiftFormCooldown(i)` returns `start, duration, enable`.
- **`GetShapeshiftForm()` returns `nil` while a form is active.** Use `isActive` from `GetShapeshiftFormInfo`.
- **`UPDATE_SHAPESHIFT_FORM` / `UPDATE_SHAPESHIFT_FORMS` never fire on form toggles.** `PLAYER_AURAS_CHANGED`, `SPELLCAST_STOP` and `UNIT_SPELLCAST_SUCCEEDED` do fire. Travel/Aquatic Form keep the action page at 1, and `UPDATE_BONUS_ACTIONBAR` only covers bonus-page forms.
- **`UPDATE_SHAPESHIFT_FORMS` does fire when a new form is learned** (live: twice on a rogue learning Stealth).
- **The active form's `texture` is swapped for a generic "active" icon.** Live: active Aspect of the Monkey/Hawk returned `Spell_Nature_WispSplode`, active Stealth `Spell_Nature_Invisibilty`; inactive entries return their own icon.

### 4.13 Experience Bar
- **Regions:** `MainMenuExpBar` is a StatusBar. `ExhaustionLevelFillBar` is a **Texture** (a solid fill: use `Set/GetVertexColor`; `SetStatusBarColor` silently no-ops). `MainMenuExpText` does not exist. The "XP cur / max" label is the FontString region of `MainMenuBarOverlayFrame` (find it by `GetObjectType()`, not by index), and native code re-shows it.
- **Native code repaints the fill colors.** FrameXML's `ExhaustionTick_OnEvent` calls `MainMenuExpBar:SetStatusBarColor` and `ExhaustionLevelFillBar:SetVertexColor` on `PLAYER_ENTERING_WORLD` / `UPDATE_EXHAUSTION`: rested blue `0, 0.39, 0.88`, normal purple `0.58, 0, 0.55`. Colors applied once get overwritten.
- **Border art:** `MainMenuXPBarTexture0-3` (race atlas, e.g. `UI-MainMenuBar-Dwarf`), each 256×10, anchored `BOTTOM` at y +3. The bar's bottom 3 units have no art. Cloning those textures failed twice (a duplicate-bar look, then distortion), so the gradient strip is final.
- `UnitXP`, `UnitXPMax`, `GetXPExhaustion`, `IsResting`, `GetRestState` behave as in `BEB/` (the reference addon). `GetRestState() == 1` means rested XP is banked; `IsResting() == 1` means the player is in a rest area now.
- **`GetXPExhaustion()` is not rested bonus XP.** On Turtle, a kill giving 31 rested bonus XP dropped it by 46.5, so remaining bonus XP = `GetXPExhaustion() / 1.5`. The rested bonus is ~75% of base XP (42 base + 31 bonus), and the rested cap is 75% of a level in bonus XP (`GetXPExhaustion()` = 1.125 × `UnitXPMax`). Blizzard's own tick (`xp + GetXPExhaustion()`) overshoots here. Other servers may differ, so the addon measures the ratio live on each character's first rested kill.
- The Turtle XP-per-level table matches `ACAB.XP_PER_LEVEL` (level 11 → 8800).
- `GameFontNormalSmall:GetFont()` works on the Font object, so no FontString is needed. `GetFont()` sizes come back as floats.

---

## 5. Open questions (unconfirmed)

- `C_Spell.UnitChannelInfo` return order (expected `name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellID`). No channel has been captured yet.
- Unknown nampower event fields (the "?" entries in §4.3). Check nampower's `EVENTS.md` before relying on them.
