# Known Problems & Gotchas

Read this when something doesn't behave the way the code suggests it should. It collects everything the 1.2.0 refactor pass found: suspected bugs nobody has confirmed yet, client quirks, code orderings that must stay as they are, and leftover tech debt.

- `docs/01-Environment-Capability-Analysis.md` stays the authority on *what the client APIs do*. This file covers *where that bites this codebase*. `env §N` points into that doc; a bare `§N` points into this file.
- Entries name file + function, not line numbers. Grep the function name.
- Code comments point here as `see known-problems.md: "<entry title>"`. Keep those titles stable.
- When a suspected bug is confirmed or fixed, move it (or delete it) and note the outcome in one line.

---

## 1. Suspected bugs (unconfirmed — verify live before fixing)

Each has a repro or a `/run` check.

Resolved in the live-verification pass: slot allocator (cleared: 4 Extra Bars sit 12 slots apart, no overlap; no 2x2 grid preset exists by design), Stance Bar form change (fixed: event fires, the native buttons just needed `ShapeshiftBar_Update()` after reparenting), native-anchor capture (cleared: all three anchors present after copy, import and on both built-in profiles), Exp Bar colors (fixed: revert to native goes through `ExhaustionTick_Update`), layout baseline delay (fixed: `SetupWizard.lua` `WaitForBaselineSettle` polls the measured native frames instead of a fixed 2 s; Modern, unlocked Vanilla and Default Modern copy all placed correctly after ~0.3 s), unlocked Vanilla bars ~76 px left (fixed: `GetDefaultVanillaData` saves live data before the wizard copies it), mod-presence detectors in `Core.lua` `ACAB:CheckRequiredMods` (cleared: each DLL removed in turn gives exactly its own chat line; without ClassicAPI the addon stays disabled with no errors), client crash during the wizard's baseline reload (closed as a one-off: seen once on a fresh Modern install, never reproduced; the client crashed occasionally before this addon existed. If it recurs, note whether the layout chat line printed and `/run print(ACABDB.pendingLayoutBaseline)`); assignment rows unlocked after an outside rebuild (fixed: `RebuildAllDefaultBarAssignmentRows` goes through `RefreshBarSettingsPage`, full gating chain), hotkey text stale after binding in Blizzard's Key Bindings UI (fixed: `UPDATE_BINDINGS` routes to `UpdateHotkeyText` on every pool button via `POOL_BUTTON_EVENT_ROUTES`).

### First-login default-bar anchor seeded at the wrong scale
- **Status:** unexplained; harmless since `GetDefaultVanillaData` saves live data before copying (the same login's recapture fixes it).
- **Where:** `Database.lua` `seedDefaultBars` / `EnsureDB`; `Core.lua` `RunLoginSequence`
- **What:** on a fresh install, `ACABDB.defaultBars[1].nativeAnchor.x` already reads 178 (Main Bar centered at UI scale 1.0) at the start of `RunLoginSequence`, while `ActionButton1` measures 254. A temporary trace in `seedDefaultBars` printed nothing before that point, so the early seed happens before chat output shows, or somewhere else.
- **Verify:** fresh install, then `/run print(ACABProfilesDB["Default Vanilla"].defaultBars[1].nativeAnchor.x)` right after the first `/reload`.

---

## 2. Client quirks (how this client behaves, and where the code relies on it)

### Lua / runtime
- **`string.match` is available despite being Lua 5.1.** `Core.lua`'s slash dispatcher / `HandleProfileCommand` rely on it, and it works live. Presumably one of the client mods supplies it. Don't "fix" it to `string.find` captures. Check: `/run print(string.match, string.gmatch)`.
- **`X and X(...)` truncates a multi-return call to one value** (stock Lua, env §2). Capture multi-return APIs (`GetPetActionInfo`: 7 values incl. `subtext` in position 2) inside a real `if X then ... end` block.
- **Lua 5.0 caps each function at 32 upvalues.** The local `luac` (5.1) allows 60 and won't catch it. Watch big settings builders when adding file-level locals; `SettingsBars.lua` peaks around 18.

### Frames, rects and layout
- **Lazy, top-down rect resolution (env §4.6).** A child read before its ancestor caches a stale rect. Discarded ancestor reads before child reads are load-bearing in:
  - `Settings.lua` `ApplySettingsHeightFromCandidates` (see §3)
  - `DefaultBars.lua` `WarmMainBarArtAncestorChain` / `GetButton1ScreenAnchor` / `ResolveNativeTopLeft`
  - `PageIndicator.lua` (`UIParent:GetLeft(); container:GetLeft()` before `RealRect`)
- **No rect until sized (env §4.6).** A frame with only `SetPoint` returns nil rects forever. Placeholder `SetWidth(1)/SetHeight(1)` at creation is load-bearing (Page Indicator container, `Settings.lua` bar-list scroll child). `MainMenuBarArtFrame` needs its native width/height re-asserted on every `ApplyMainBarArtPosition` (order: size → scale → ClearAllPoints → SetPoint).
- **Same-name `CreateFrame` makes a second frame (env §4.7).** `SettingsBars.lua` `RebuildDefaultBarAssignmentRows` and `RefreshBarList` pool their named frames: one fixed name per pool slot (barId / form index), created once and re-shown after that. Any path that creates such a frame again instead of reusing it needs a per-rebuild name counter. The Setup Wizard uses fixed names and is only safe because it's a build-once singleton: if steps ever get rebuilt, suffix a counter on every name.
- **ScrollFrame must stay paired with its original scroll child** (`Settings.lua` `CreateSettingsFrame`, `CreateWideContentScrollFrame`). Pointing a ScrollFrame at a new child leaves that child unresolvable. Build a new pair instead.
- **FontString anchored only by TOPLEFT+TOPRIGHT won't wrap.** Set an explicit `SetWidth` before `SetText`, then read `GetHeight` (`Settings.lua` `SetProfileLockBannerMessage`).
- **Strata survives reparenting.** ActionBarUp/DownButton keep `MainMenuBarArtFrame`'s MEDIUM strata after `SetParent`. `PageIndicator.lua` `ApplyPageIndicatorStrata` reasserts LOW + explicit levels on every apply. Bars (`Bar.lua` `ApplyBarShape`) re-set LOW/level 10 on every shape pass, because page/stance swaps or `MainMenuBarArtFrame:Raise()` otherwise bury Bar 1 (env §4.8).
- **Reparenting raises a button's level, not its children's.** Native Pet/Stance buttons moved into their container leave `<name>Cooldown` / `<name>AutoCast` behind the icon (GCD spiral invisible). `PetStanceBars.lua` `LiftButtonChildrenAboveButtons` re-lifts them after every reparent (`CreatePetBarNativeContainer`, `CreateStanceBarContainer`, `RebuildStanceBarContainer`).
- **Edit-mode overlays are parented to UIParent** (`ElementEngine.lua` `EnsureContainerOverlay`) so all overlays compare FrameLevel in one tree. Hiding an element never hides its overlay: every disable path must `overlay:Hide()` + `EnableMouse(false)` itself. Overlapping overlays need distinct explicit levels (Key Ring 150 vs default 100).
- **Page Indicator is laid out from `GetPoint` data, not rect deltas** (`PageIndicator.lua` `CreatePageIndicatorContainer` / `ApplyPageIndicatorShape`). Right after login, sibling rects can still be cached from before the art moved. `MainMenuBarPageNumber` (FontString) has no `GetEffectiveScale`, so `ACAB:PixelSetPoint` falls back to plain `SetPoint`.
- **Latency Bar Modern reset measures one frame late** (`NativeElements.lua` `ResetLatencyBarLayoutToModernBase`). Overlay rects don't reflect `SetScale(1)` until the next frame. `ApplyModernCornerClusterLayout` takes every measurement before any `Apply*Position`.
- **Simple-page reset refresh is deferred one frame** (`SettingsBars.lua` `CreateSimpleBarPage`), because the element's new size resolves next frame. It uses `ACAB:DeferFit`. If `DeferFit` ever starts coalescing, these need their own next-frame helper.

### Native frames and FrameXML
- **Native code re-anchors wrapped frames without `ClearAllPoints`**: Key Ring, Latency Bar, Micro Menu and Bag Bar buttons (`MainMenuBarBackpackButton`, `QuestLogMicroButton` seen), the art frame. `ElementEngine.lua` `InstallReanchorGuard` swallows every unflagged `SetPoint`/`ClearAllPoints` and records the last swallowed anchor in `frame.ACABSwallowedAnchor`, which `Core.lua` `WaitForWrappedFrameAnchorSettle` polls. Every own re-anchor must set the element's guard flag around it. `relativeTo` can arrive as a name string, and indexing a string errors, so check for the string first. `ApplyGridAnchoredShape` hard-codes `ACABApplyingMicroMenuPosition`: fine while Micro Menu is the only grid container.
- **`ShapeshiftBar_Update` checks `MultiBarBottomLeft:IsShown()`** to pick Stance Bar border art. `DefaultBars.lua` `ForceShowMultiBarBottomLeft` force-shows it with `Hide` neutered, then re-runs `ShapeshiftBar_Update()` once. Don't clean either up.
- **Stance assignment keys off the active form, not the action page** (`DefaultBars.lua` `GetDefaultBarSlotForIndex`). Travel/Aquatic Form leave the page at 1. `GetShapeshiftForm()` returns nil here, so use `GetShapeshiftFormInfo`'s `isActive` (env §4.12).
- **`ShapeshiftButton` backdrop must be a separate frame** (`PetStanceBars.lua` `ApplyStanceBarBorderStyle`). `SetBackdrop` on the real button draws over the icon and greys it out.
- **`SHOW_MULTI_ACTIONBAR_1-4` don't survive logout (env §4.5).** `Database.lua` `SeedOneDefaultBar` seeds `enabled` from `DEFAULT_BAR_GRID`.
- **Edit mode's Escape exit is a keybinding swap** (`Core.lua` `ACAB_EditModeEscapeFire` / `Enable/DisableEditModeEscapeBinding`). An `EnableKeyboard(true)` capture frame blocks every other key on this client. So `ESCAPE` is bound to `ACABEDITMODEESCAPE` (bindings.xml → plain global), never saved, and reverts on reload. Don't add `SaveBindings` here; keep the global.
- **Macro slots use our own parser, not the client's pick, and CleveRoid's only for `[conditions]`** (user decision). SuperCleveRoidMacros replaces the global `GetActionTexture`, `IsUsableAction`, `IsActionInRange`, `IsCurrentAction`, `GetActionCooldown`, `GetActionCount`, `IsConsumableAction` and `GameTooltip.SetAction` for macro slots, picking the first action whose `[conditions]` pass (live: the bow icon on a "/cast Serpent Sting + /cast !Auto Shot" macro, `?` while Auto Shot runs). `Button.lua` `ResolveMacroTarget` picks the target itself: an explicit `#showtooltip`/`#show`/ShaguTweaks `--showtooltip` name; else, for macros containing `[` with CleveRoid loaded, the first `;` option whose conditions pass by `CleveRoids.TestAction(cmd, option)` (re-tested on every 0.2 s range tick, `UpdateConditionalMacroPick`, repaint only on change) that isn't Auto Shot, Attack, Shoot or `?`-prefixed; else the first `/cast`/`/use`/`CastSpellByName("...")` that isn't (first `;` alternative). That target drives icon (always the spell's or item's own, even over a custom macro icon), tooltip, count, cooldown, quality ring and range/usable tint (nampower `IsSpellUsable`/`IsSpellInRange` by spell name). `ACAB:PrintMacroAddonNote` prints a one-line note for CleveRoid users at login.
  - **Macro glow** ignores `IsCurrentAction` (CleveRoid answers it through a proxy slot, which left Auto Shot glows stuck): Auto Shot/Shoot glow while `START/STOP_AUTOREPEAT_SPELL` says so, Attack per `PLAYER_ENTER/LEAVE_COMBAT`, other spells while `SPELLCAST_START`'s `arg1` names them (cast-time spells only; channels and instants never glow).
  - **CleveRoid's own stored pick isn't used.** Live, `CleveRoids.GetAction(slot).active` was `nil` for "/cast [mod:shift] Arcane Shot; Serpent Sting" with no modifier held, and with nampower key events (`hasKeyEvents` true) CleveRoid neither polls Shift/Ctrl/Alt nor handles their `KEY_DOWN`/`KEY_UP` (key codes 0/1/2), so its pick never follows modifiers (its bug; Blizzard/pfUI bars show the same stale icon). Testing each option with `TestAction` ourselves avoids both.
  - **Out-of-stock items** keep their icon, greyed, via a session-only cache (`knownItemTextures`); after a `/reload` with none left, the macro's own icon shows until one is looted.
  - ShaguTweaks-extras "Macro Icons" only repaints Blizzard's own (hidden) buttons; "Macro Tweaks" supplies `/use` and `/equip`; "actionbar-reagents" only writes Blizzard button counts. ShaguTweaks "Reduced Actionbar" moves native bar frames this addon also manages; not checked here.
- **Native-mode Pet/Stance bars are outside hoverbind.** They wrap real `PetActionButton` / `ShapeshiftButton` frames, so they bind only through Blizzard's Keybindings UI.

### Input / locking
- **Locking controls** (`Settings.lua` `LockControl` / `LockControlKeepingTooltip`):
  - `EnableMouse(false)` doesn't block a templated Button's OnClick; it also needs `Disable()`.
  - Both kill OnEnter/OnLeave, and with them tooltips. A disabled CheckButton gets no OnEnter at all.
  - A `UIDropDownMenuTemplate` click goes through its `<name>Button` child.
  - Plain Frames have no OnClick.
  - To lock while keeping a "why is this locked" tooltip, use `LockControlKeepingTooltip` (`ACABLocked` flag, honored by `CreateLabeledCheckbox`'s OnClick wrapper).
- **Position sliders must keep `SetValueStep(0)`** (`UIWidgets.lua` `CreatePositionAxisSlider`). A non-zero step re-snaps to a grid that isn't pixel-aligned. Drag values get pixel-snapped by hand; stepper/typed commits bypass that via `ACAB:SetSliderValueUnsnapped`.
- **`SetMinMaxValues` fires `OnValueChanged` like a real drag.** Set `suppressApply`/`suppressSnap` before changing a range and clear them after the last `SetValue` (`SettingsBars.lua` `RefreshSimpleBarPage` / `RefreshBarSettingsPage`). `SetValue` with an unchanged value doesn't fire, hence the explicit `xAppliedValue`/`yAppliedValue`.
- **Never `SetValue` a slider from its own `OnValueChanged`.** It breaks the native drag for the rest of that gesture. Position pages read `page.*AppliedValue or slider:GetValue()`.

### Experience Bar (env §4.13)
- **Region map:**
  - `MainMenuExpBar` is a StatusBar.
  - `ExhaustionLevelFillBar` is a **Texture** (use `Set/GetVertexColor`; `SetStatusBarColor` silently no-ops).
  - `MainMenuExpText` doesn't exist. The native XP label is a FontString region of `MainMenuBarOverlayFrame`, found by `GetObjectType()`.
  - Border art is `MainMenuXPBarTexture0-3`.
- **Native code repaints the Exp Bar fill colors.** FrameXML `ExhaustionTick_OnEvent` calls `MainMenuExpBar:SetStatusBarColor` (rested blue `0, 0.39, 0.88` / normal purple `0.58, 0, 0.55`) and `ExhaustionLevelFillBar:SetVertexColor` on `PLAYER_ENTERING_WORLD`/`UPDATE_EXHAUSTION`. `ExperienceBar.lua` `InstallExpBarColorGuard` overrides both methods on the instances and swaps in the saved color while Better Experience Bar is on. Check: `/run local r,g,b=MainMenuExpBar:GetStatusBarColor() print(r,g,b,GetRestState())`.
- **Native XP label re-shows itself.** `ApplyBetterExpBarVisual` neuters its `Show` while Better Experience Bar is on, capturing the real `Show` once, before the first neuter.
- **Bottom border is a gradient strip, final** (`EnsureExpBarBottomBorderStrip`). Two native-art clone attempts rendered distorted. Don't retry without a live tex-coord dump.
- **Text overlay must be a HIGH-strata child of `MainMenuExpBar`** (`EnsureExpBarTextOverlay`). Parented to UIParent it measured 0.9× the bar and drifted.
- **Rested tick texture paths must use the installed folder name** `Interface\AddOns\AlternativeClassicActionBars\...`. A wrong segment renders a blank tick silently.
- **Rested overlay uses bonus XP, not `GetXPExhaustion()`** (env §4.13). `ExperienceBar.lua` `GetRestedBonusXP` divides by `ACABCharDB.restPoolPerBonusXP`, which `CalibrateRestPoolFromXPMessage` (Events.lua `CHAT_MSG_COMBAT_XP_GAIN`) measures once per character on the first rested kill: pool drop ÷ first number in the chat line's parentheses, with the drop taken from `TrackRestPool` within 2 s of the message. Until then the ratio is 1 (Blizzard's native formula, too long on Turtle). The fill, tick and "Rested" text all read it. Recalibrate: `/run ACABCharDB.restPoolPerBonusXP=nil` then kill a mob while rested. Unverified: the chat pattern on non-English clients.
- **`GetRestState() == 1`** (banked rested XP) gates the rested overlay; **`IsResting() == 1`** (in a rest area now) gates only the glow/pulse. Don't swap them. `GetFont()` sizes come back as floats, so round them.

---

## 3. Fragile orderings (code that must stay exactly as written)

### Settings height-fit top-down resolve pass
- **Where:** `Settings.lua` — `ApplySettingsHeightFromCandidates`
- **What:** After `SetVerticalScroll(0)` it does `scrollChildPanel:GetTop()`, then `GetBottom()` on every candidate, then `GetBottom()` on the General panel's static anchor chain, all discarded. This is the env §4.6 fix, and three "equivalent" rewrites all brought the bug back.
- **Keep:** the block byte-for-byte, including the per-call `resolveNames` table and loop order. A new General-tab control hanging off an unmeasured static anchor needs that anchor added to `resolveNames`. Symptom if broken: toggling Global Spacing makes the controls below it unreachable.
- **Related:** `MeasureDeepestExtent` must stay a live-position delta (`referenceTop - frame:GetBottom()`), since the window is movable. The `Fit*` candidate lists feed this pass in order: any conversion to name tables must produce an identical array.

### Inline dropdown SetParent after CreateFrame
- **Where:** `UIWidgets.lua` — `ACAB:CreateInlineDropdown`
- **What:** The explicit `SetParent(parent)` right after `CreateFrame(..., parent, ...)` is most likely a no-op (env §4.7 says a reused name makes a new frame, not a reparented old one). It's kept because removing it is risk with no gain. The `OnShow` handler that reapplies `UIDropDownMenu_SetWidth`/`SetText` **is** load-bearing: dropdowns built while hidden otherwise render with a fragmented skin and a blank label.

### Fade strip textures live on the parent
- **Where:** `UIWidgets.lua` — `ACAB:CreateFadeStrip` / `ACABFadeStripMixin`, `ACABListRowMixin:OnLoad`
- **What:** Strip textures are created on `parent` (ARTWORK), not on a child frame, so they draw behind the parent's own OVERLAY text. Cross-frame draw order is decided by frame level, not layer. The strip is a plain table with its own `SetPoint`/`Show`/`Hide`/`IsShown` driven off `leftTex`. `hoverStrip` must be created after `selectStrip` so it draws on top. Never turn it into a child frame.

### Capture before Mixin / before neutering
- `Mixin()` copies functions onto the instance. Capture native methods **before** calling it (`UIWidgets.lua` `CreateListRow`), or you capture the override and recurse.
- Same rule for the Exp Bar `Show` neuter (§2) and any other "capture original, then replace" pattern.

### Gating call order in settings page refreshes
- **Where:** `SettingsBars.lua` — tail of `RefreshBarSettingsPage` and `RefreshSimpleBarPage`
- **What:** `ApplyProfileLockGating` resets alpha/EnableMouse/Enable on every listed control, and always unlocks `enableCheckbox` on numbered default bars. Everything that only dims or locks further must run after it: grid-layout lock, Page-Indicator grouped lock, the Main Bar art dim, bar 5's enable lock, global-override gating, Use Vanilla / Condense `LockControlKeepingTooltip`, and `ApplySimpleElementGroupedLock` (which must also follow `ApplyDefaultLayoutGating`). Append new dim-only locks after these.

### InstallGroupLockGuard wraps existing handlers
- **Where:** `SettingsBars.lua` — `ACAB:InstallGroupLockGuard`
- **What:** It captures the control's current OnEnter/OnLeave/OnClick (OnMouseDown for sliders), so it must be installed after the control's own scripts exist. Setting OnClick after guarding bypasses the lock.

### Simple-page scale change needs a full page refresh
- **Where:** `SettingsBars.lua` — `CreateSimpleBarPage` Scale slider `onChange`
- **What:** Scale compensates stored x/y, so the handler must call `RefreshSimpleBarPage(key)`, which re-syncs X/Y before re-clamping. `RefreshSimplePositionSliderRange` alone makes the element jump.

### ResetAllElementsToVanillaLayout ordering
- **Where:** `SettingsBars.lua` — `ACAB:ResetAllElementsToVanillaLayout`
- **What:**
  - Each element resets layout before position, so position converts at the final size/scale.
  - Pet/Stance `useNative*` flags are forced before `CreatePetBarNativeContainer`/`CreateStanceBarContainer`. The "effective" checks only force native while `useDefaultLayout` is on, which isn't the wizard path.
  - `ReflowStanceBarForBar2Toggle` runs last.
  - New resets go after the flag block and before the final Stance reflow.

### Scale reset writes scale directly, before resolving the native anchor
- **Where:** every native-element reset:
  - `ElementEngine.lua`: `ACAB:ResetScaleAndResolveNative` (Latency/Cast/Exp Bar)
  - `NativeElements.lua`: `ResetKeyRingPosition`
  - `Tooltip.lua`: `ResetTooltipLayout`
  - `PetStanceBars.lua`: `ResetPetBarNativeLayout`
- **What:** They write `ACABDB.<x>Scale = 1` + `frame:SetScale(1)` directly. The public `Set<X>Scale(1)` would run `CompensateScaleKeepingCornerFixed` against the old scale and inflate the restored position. Key Ring must use `SetKeyRingOwnScaleForEffective(frame, 1)`, because it inherits the art frame's scale.

### EnsureDB ordering and one-shot flags
- **Where:** `Database.lua` — `ACAB:EnsureDB`
- **What:** Seeds read each other:
  - `lastAppliedVanillaStyle` reads `useDefaultLayout`/`modernBorderStyle`.
  - Key Ring hover seeds from Bag Bar hover *before* Bag Bar's own seed.
  - Bar seeding reads `GetCurrentButtonSizeBaseline`.

  One-shot flags must never be reset: `migratedDefaultBarSwapSentinel`, `snapDefaultCorrectedOnce`, `spacingRecaptureDone`, `ANCHOR_RECAPTURE_FLAGS`. A `SCHEMA_VERSION` bump wipes `ACABDB.bars`, which is why migrations use flags. `expBarTextColor` reseeds on `not x`; everything else on `== nil`.
- **Keep:** append new defaults only; never reorder or change an existing default. Diff an `ACABDB` dump before/after touching it (an offline stub harness was used for this during the refactor).

### Profile data integrity
- **Recapture mutates in place.** `Database.lua` `RecaptureDefaultBarNativeAnchors` must mutate cfg tables in place, since `bars[id].config` *is* `ACABDB.defaultBars[id]`. Replacing the table detaches live bars.
- **CreateProfile falls back to the live `ACABDB`**, never an empty table. `ACABProfilesDB["Default"]` only exists after a logout or switch, and an empty fallback leaves new profiles without `defaultBars`.
- **Profile writes hit both `ACABDB` and `ACABProfilesDB`.** Logout / `ReloadUI` runs `SaveActiveProfileData`, which writes live `ACABDB` back under `activeProfileName`. Deleting the active profile must also repoint `activeProfileName`.
- **Export format is byte-stable** (`TBVPROFILE1:`). Never add whitespace to `ProfileIO.lua` `SerializeValue`, or older parsers reject it. The parser doesn't trim bare tokens (`[1]=false }` fails), and numbers round-trip at 14 significant digits.

- **Sanitizer key lists are hand-kept.** `ACAB:SanitizeProfileData` (Database.lua) type-checks only the fields named in its `SANITIZE_*` lists plus `defaultBars`/`bars`; it runs on every saved profile at login and on imports. A new persisted field with a crash-prone type must be added there.
- **Coverage:** every `ACABDB` field the code reads is type-checked, except one-shot migration flags (never touched on purpose) and legacy fields nothing reads anymore (`disableBlizzardArt`, `groupedElementOffsets`, `mainBar*Assignment`/`*Enabled`). Per-bar `nativeAnchor`/`fixedActionSlots` are structural: a bad one resets all of `defaultBars`, like a bad position. Other per-bar fields (`SANITIZE_BAR_*`) drop only that field, since every reader is nil-safe. `customGridSize` must stay above 0 because the layout grid steps by it.
- **Import limits:** 256 KB string, 12 table levels, finite numbers only, string/number keys only, `schemaVersion` must be a number. Deep-recursion behavior on the real Lua 5.0 client is unverified (harness ran Lua 5.1); the depth cap makes it moot.
- **Import never targets a built-in profile** (`ApplyImportedProfileData` and `ShowImportProfileDialog` refuse). Duplicate keys in an import: last one wins.

### Setup Wizard baseline write and resume
- **Where:** `SetupWizard.lua` — `BuildBaselineData`, `WriteTargetProfile`, `ApplyBaselineAndReload`, `SaveResumeState`
- **What:**
  - `lastAppliedVanillaStyle` must be set together with `modernBorderStyle`, or the next login is treated as a live style switch.
  - `WriteTargetProfile` must repoint the live `ACABDB` and `activeProfileName` at the new data before `ReloadUI`, or the logout-time `SaveActiveProfileData` writes the old data over it. Create mode saves the old active profile first.
  - The resume state (`ACABCharDB.setupWizard`) is re-saved on every page `ShowStep` and cleared only by Finish, the X button, or a profile mismatch at login. Don't clear it from an `OnHide` (untested whether a reload fires `OnHide` before unloading).
  - `ApplyPendingLayoutBaseline` places the Exp Bar before `ApplyModernLayoutGeometry` (see "Setup Wizard reads saved Exp Bar position").

### Settings window wizard mode
- **Where:** `Settings.lua` (`GetSettingsChromeBottom`, wide-view `applyScrollbarReserve`, `ApplyBarsViewScrollbarReserves`, `FitSettingsWindowToBarPage`), `SettingsBars.lua` `ShowBarPage`, `SetupWizard.lua` `SetChromeShown`
- **What:** While `settingsFrame.wizardMode` is on, the bar list stays hidden (its rows are not measured), wide views reserve the step list's width, the bottom chrome grows for the Back/Next row, and the viewport is floored to `wizardStepList.requiredHeight`. Right-click / `/acab settings` navigation is swallowed (`IsSetupWizardActive`) so the wizard keeps the page. `Exit` must reset `currentView`/`activeBarId`, or the next normal open fits a hidden view.

### Pool-button construction order
- **Where:** `Button.lua` — `ACABButtonMixin:Init`
- **What:**
  - `equipRing` exists before `ApplySize`.
  - Native font capture runs after the `hotkey`/`count` FontStrings exist and before their `SetFont`.
  - The reparented `PetActionButton<n>AutoCast` Model must never get `SetModel()` again, which resets it to a white plane (resize via `SetModelScale`).
  - Button and cooldown set LOW strata explicitly (below bags).
  - `ApplyBorderStyle` shares the `Init` helpers, so new border pieces go there.

### Pool-button event dispatcher
- **Where:** `Button.lua` — `RegisterPoolButton`, `MovePoolButtonActionSlot`, `PoolButtonDispatcher_OnEvent`, `POOL_BUTTON_EVENT_ROUTES`
- **What:**
  - Buttons register no events themselves. One dispatcher frame routes each event to the action/pet/stance list in `POOL_BUTTON_EVENT_ROUTES`; `ACTIONBAR_SLOT_CHANGED` looks up `actionSlotButtons[arg1]` (0/nil refreshes all).
  - Every `btn.actionSlot` change must go through `ACABButtonMixin:Rebind`, or the slot map goes stale and that button stops refreshing on slot changes.
  - The dispatcher copies `event`/`arg1` into locals before looping, since per-button code can clobber the globals.
  - It's created on the first `Init`, not at file load, so it registers after `Events.lua`'s frames (same order as the old per-button registration). Pool buttons are never destroyed, so the lists only grow.
  - Pet/stance buttons get no `ACTIONBAR_SLOT_CHANGED` for their own small slot index anymore (was an accidental match against action slots 1-10).
  - `PLAYER_AURAS_CHANGED` doesn't `Refresh` stance buttons: `UpdateStanceFormChange` compares `GetShapeshiftFormInfo`'s texture/isActive/isCastable against the cache `Refresh` writes, and only on a change updates icon + glow (plus every stance cooldown). `UPDATE_SHAPESHIFT_FORMS` (fires on learning a form), `PLAYER_ENTERING_WORLD` and `Rebind` still do a full `Refresh`.

### Removed intra-addon existence guards
- **Where:** `Bar.lua`, `Button.lua`, `HoverBind.lua`, `Core.lua`, `Events.lua`
- **What:** Same for `C_Timer` hedges: ClassicAPI is enforced at login (`CheckRequiredMods`, the only place that still checks `type(C_Timer)`), so tickers/`C_Timer.After` calls are unguarded. Guards like `if ACAB.RefreshBarSettingsPage then` were dropped because every guarded member is defined at the top level of a file that always loads, and every call runs after login. So:
  - Nothing may call `CreateActionButton` / `ApplyEditModeVisual` / `ApplyGlobalButtonStyle` / `ApplyHoverOnlyState` at file-load time.
  - `HoverBind.lua`'s top-level `customBindTargets = {}` must run before any button is created.
  - `Core.lua`'s hover-fade code calls `ACAB:GetCursorPositionUIScale` (defined later, in ElementEngine.lua): runtime-only.

### Shared single-frame element helpers
- **Where:** `ElementEngine.lua` — "Single-frame element helpers" section: `SetElementShown`, `WriteSavedPositionXY`, `StoreCompensatedScale`, `ResetScaleAndResolveNative`, `ReadNativeAnchor`, `SeedNativePosition`, `CopyNativePosition`
- **What:** NativeElements, PetStanceBars and ExperienceBar all call these. `StoreCompensatedScale` does `EnsureDB` + clamp + CENTER compensation + write, but never `SetScale`/apply; each caller still applies. Bag Bar, Micro Menu and Stance Bar apply scale through their shape pass. Keep the signatures, and re-check all three files when changing one.
- **Not covered, on purpose:**
  - Pet Bar native mode stores on the shared `defaultBars[PET_BAR_ID]` cfg, not an `ACABDB` field, and must mutate it in place.
  - Key Ring reset uses its own-scale path.
  - Tooltip scale keeps a corner fixed, not the center.
  - `SetDefaultBarEnabled` has its own Pet Bar logic.

### Cross-file calls that only work at runtime
- **`ShowBarPage` → `HideWideViews`.** `SettingsBars.lua` `ShowBarPage` calls `ACAB:HideWideViews` (SettingsGeneral.lua, loads later, closes over `WIDE_VIEWS`/`WIDE_VIEW_ORDER`). Never call `ShowBarPage` from top-level code. A new wide view only needs a `WIDE_VIEWS` + `WIDE_VIEW_ORDER` entry.
- **`/acab profile` → shared profile dialogs.** `Core.lua` calls `ACAB:ShowExportProfileDialog` / `ShowImportProfileDialog` / `ShowCopyProfileDialog` (SettingsGeneral.lua) from the slash handler only.
- **Copy dialog captures its target at open.** The Profiles-tab copy dialog captures its target profile when it opens, not on Accept. That's only correct because every in-session change of `ACABCharDB.activeProfile` is followed by `ReloadUI()`. If profiles ever switch without a reload, re-read the target in Accept.
- **Stance count clamp.** `ACAB:GetClampedLiveStanceCount` (Core.lua) reads `MAX_STANCE_BUTTONS` from DefaultBars.lua, so call it at runtime only.

### Other must-stay spots
- **Key Ring grouped placement uses a login snapshot.** `NativeElements.lua` `CaptureKeyRingNativeTopLeft` must run in `RunLoginSequence` before the Bag Bar or Main Bar art moves. Key Ring's native anchor is `RIGHT` of `CharacterBag3Slot` (x -5), and the grouped Bag Bar itself moves that slot by its `pixelCorrection`, so resolving the anchor live put Key Ring 1-2 px high after any regroup (live-confirmed: art-mode dropdown, not fixed by a later `ApplyMainBarGroupedElements`). Key Ring's `pixelCorrection`/`pixelNudgeY` are tuned against the native slot position.
- **Extra Bar defaults follow the reference bar.** `Database.lua` `GetDefaultExtraBarLayout` reads the built reference bar's current cfg (size, spacing, grid, position) and places the Extra Bar one pitch (frame + `GetBarEffectiveSpacing`) above/left of it; before bars exist it uses the reference bar's Reset-to-Vanilla values. `GetExtraBarStackPitch` must use the same gap, or Stance/Pet Bar restack off by the spacing difference.
- **Stance gap capture before bars.** `PetStanceBars.lua` `CaptureStanceBarNativeGap` runs in the login sequence before `CreateFixedSlotDefaultBars`, which collapses the native anchor. (The value itself is dead, see §4.)
- **Setup Wizard reads saved Exp Bar position.** `DefaultBars.lua` `GetModernBaseExpBarClearance` must read the saved Exp Bar position, not a live rect. `ApplyPendingLayoutBaseline` writes it first.
- **Exp Bar layered under Latency Bar.** `ExperienceBar.lua` `ApplyExpBarPosition` copies Latency Bar's strata at level −1. This interacts with `MainMenuBarArtFrame`'s pinned LOW/level-5 masking (env §4.8), so change both together.
- **Wheel resize.** `Bar.lua` `ACAB:ResizeBarFromWheel` is shared by the bar overlay and the button handler. The button's wheel handler must stay installed, since it swallows camera zoom over buttons outside edit mode.
- **Login stages.** `Core.lua` `RunLoginSequence` runs each step through `RunLoginStage` (`xpcall` → client error handler, then continue). Only the "profile" stage aborts the sequence (live-confirmed: a forced "tooltip" failure left every other element in place; a forced "profile" failure disabled the addon cleanly). A failed stage leaves later stages running on whatever it left half-built, so expect follow-up errors from the stage that broke first; report that one. New steps go into an existing stage or a new named one, in the same position the order comments require.
- **Login timing.** The settle polls (`Core.lua` `WaitForNativeBarSettle`, `WaitForWrappedFrameAnchorSettle`, `WaitForPostLoginSettleThenVerify`) are load-bearing: `stableCount` resets on any mismatch/nil, the check runs after `elapsed++`, and only a timeout without settling warns. Test any change with `/reload` and a fresh login.

---

## 4. Tech debt & cleanup candidates

### Dead code kept on purpose (would change saved data or chat output)
- **`stanceBarNativeGap`.** `PetStanceBars.lua` `CaptureStanceBarNativeGap` and `ACABDB.stanceBarNativeGap` are captured but never used for layout (`GetStanceBarBaselineY` uses fixed `PET_BAR_NATIVE_GAP`). Removing them changes a WARNING print and saved data. Remove together: the capture, its two call sites, and the EnsureDB self-heal.
- **Legacy profile fields.** The reserved "ModernBase" profile name (`Database.lua` `MODERN_BASE_PROFILE_NAME`) is legacy but still hides old `ACABProfilesDB["ModernBase"]` entries. "Default" (`LEGACY_DEFAULT_PROFILE_NAME`) stays reserved so a new user profile can never be mistaken for the pre-rename Default Vanilla. `disableBlizzardArt`, `mainBarPaginationEnabled`, `mainBarStanceSwapEnabled`, `mainBarPageBarAssignment` and `mainBarStanceBarAssignment` stay in saves forever. Cleaning up needs a one-shot migration.
- **`Button.lua` stubs.** The stance tooltip fallback for missing `GameTooltip.SetShapeshift` never runs, stock-API guards never fail, and `OnDragStop` is empty (still assigned in `Init`, so it stays).

### Tech debt
- **Pet Bar reflow rewrites `cfg.nativeAnchor.y`.** `PetStanceBars.lua` `ReflowPetBarForBar3Toggle` does this, so treat the Pet Bar `nativeAnchor` as "last default-stack position", not the true capture.
- **Extra Bar fallback size.** `Database.lua` `GetDefaultExtraBarLayout` returns `BUTTON_SIZE` on the normal path but `GetCurrentButtonSizeBaseline()` on the fallback path.
- **Two screen-size reads.** `Settings.lua` `GetScreenCoordinateRange` and `Bar.lua` `RebuildLayoutGrid` use `UIParent:GetWidth()/GetHeight()` instead of `GetUIParentAnchorSize`. It's harmless in both today (legacy range only / covered by overshoot lines). In `RebuildLayoutGrid`, `GetLayoutGridSpacing()` is already in local units, so don't divide it by effective scale.
- **Sidebar rows follow `getElementFrame`.** `SettingsBars.lua` `RefreshBarList` shows a simple-page row only when its config's `getElementFrame()` is non-nil. New simple pages need a `getElementFrame`.
- **Composed names hide greppable identifiers.** The Pet/Stance "Use Vanilla" checkbox name and field are built by concatenation (`CreateUseVanillaBarCheckbox`). Grep the factory name.

### Performance (measured as fine so far; look here first if something stutters)
- **Main Bar drag.** Every tick re-applies the art frame (texture Hide/Show redraw, which is load-bearing) plus all grouped elements, each with a fresh hover closure.

Done: range-ticker write cache (`rangeKey` in `UpdateRange`), Pet Bar layout coalescing (`petLayoutPending` in `Refresh`), rested-glow pulse stops with the Exp Bar, pooled bar-list rows (`RefreshBarList`), grid swatches and assignment rows (`RebuildGridSwatches`, `RebuildDefaultBarAssignmentRows`), one shared event dispatcher for all pool buttons (`Button.lua` `POOL_BUTTON_EVENT_ROUTES`), hover-bind tint ticker reuses one callback and one ref table (`HoverBind.lua` `ForEachButton`).

### Remaining duplication
- **`AppendCandidate`** is file-local in both `Core.lua` (grid-snap candidates) and `Settings.lua` (height-fit). It was left alone because the Settings copy sits inside the resolve-pass machinery. If shared, define it in Core.lua and keep the candidate order.
- **Absolute-position capture.** `NativeElements.lua` `CaptureKeyRingPositionIfNeeded` and `ExperienceBar.lua` `CaptureExpBarPositionIfNeeded` still hand-roll the same code (GetLeft/GetTop → UIParent units → TOPLEFT write → `ReadNativeAnchor`). An `ACAB:CaptureAbsolutePosition(frame, posField, nativeField)` would cover both. `Database.lua` `CaptureNativeAnchor` is different on purpose: it returns nil on a missing scale.
- **Pet Bar native helpers.** Pet Bar native-mode position/scale/reset would need the single-frame helpers to take a table instead of a field name.
- **Two backdrop pairs** are still inline:
  - tile 16 / edge 12 / inset 2: `UIWidgets.lua` dialog error banner + `Settings.lua` `CreateProfileLockWarning`
  - tile 8 / edge 8 / inset 2: `Settings.lua` `ApplyPanelBackdrop` + `SettingsBars.lua` `CreateGridSwatch`

  They could join `ACAB.DIALOG_BACKDROP` / `SMALL_BACKDROP` / `MODERN_BACKDROP` in UIWidgets.lua.
- **Modern button factory.** `SetupWizard.lua` `CreateWizardButton`, `UIWidgets.lua` `ACAB:CreateResetButton`, and hand-rolled `CreateFrame` + `StyleModernButton` sequences elsewhere could share one `ACAB:CreateModernButton(parent, config)` with a danger/prominent `variant`. `CreateResetButton` anchors before styling, the others style first, so confirm live that the order doesn't matter.
- **Login settle polls.** `Core.lua` has three near-identical tickers. See the login-timing entry in §3 before unifying.
- **`Fit*` candidate lists.** `Settings.lua` (~60 lines of `AppendCandidate` calls) could be name tables. The resulting array must be identical and in the same order.
- **Default-bar overlays.** `ElementEngine.lua` `EnsureContainerOverlay`'s overlays have wheel handlers similar to `ACAB:ResizeBarFromWheel`.

### Decomposition ideas (need `.toc` + CLAUDE.md updates)
- **`SettingsBars.lua`** (~3800 lines): the simple-page subsystem is ~1100 self-contained lines. The Force-Vanilla cascade isn't UI code. Shared `CreateReflow*` locals would need to become `ACAB:` methods first, which also helps the upvalue cap.
- **`Database.lua`**: the first-login/create-profile dialogs are UI.
- **`SetupWizard.lua`**: the baseline geometry pass (`ApplyModernLayoutGeometry`, `ApplyPendingLayoutBaseline`) isn't wizard UI and could move next to the Modern layout code in `DefaultBars.lua`.
- **`UIWidgets.lua`**: `ACABDialogMixin` is the largest self-contained unit.
- **`Bar.lua`**: the layout-grid overlay and the Extra Bar policy are separable.
