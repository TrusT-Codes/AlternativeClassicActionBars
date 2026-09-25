# Known Problems & Gotchas

Read this when something doesn't behave the way the code suggests it should. It collects everything the 1.2.0 refactor pass found: suspected bugs nobody has confirmed yet, client quirks, code orderings that must stay as they are, and leftover tech debt.

- `docs/01-Environment-Capability-Analysis.md` stays the authority on *what the client APIs do*. This file covers *where that bites this codebase*.
- Entries name file + function, not line numbers. Grep the function name.
- Code comments point here as `see known-problems.md: "<entry title>"`. Keep those titles stable.
- When a suspected bug is confirmed or fixed, move it (or delete it) and note the outcome in one line.

---

## 1. Suspected bugs (unconfirmed — verify live before fixing)

None of these were fixed during the refactor. Each has a repro or a `/run` check.

### `/acab profile copy|import|export` bypass the Default-profile gate
- **Where:** `Core.lua` — `ACAB:HandleProfileCommand`
- **What:** The Profiles tab hides Export/Copy/Import/Delete while the Default profile is active, and `IsDefaultProfileActive` states Default can never be edited. The chat commands skip that gate: `copy` and `import` overwrite Default's saved data. `delete` is safe (refuses "Default" by name).
- **Verify:** On Default, `/acab profile copy <other>`, accept, `/reload`. If Default's layout changed, gate the branches on `self:IsDefaultProfileActive()`. The refusal message text still needs deciding.

### Early XP/rest events can run EnsureDB before the login sequence
- **Where:** `ExperienceBar.lua` — `ACAB:BetterExpBarOnEvent` / `UpdateBetterExpBarText`; registered in `Events.lua` (`betterExpBarEventFrame`)
- **What:** `PLAYER_XP_UPDATE`/`UPDATE_EXHAUSTION`/`PLAYER_LEVEL_UP`/`PLAYER_UPDATE_RESTING` are registered at load, but `ResolveActiveProfile` + `EnsureDB` only run after `PLAYER_ENTERING_WORLD` + the settle poll. An event in that window can:
  - error on a fresh install (`ACABDB` nil)
  - otherwise seed defaults into the pre-profile account-wide `ACABDB` (native anchors captured before settle)
  - use up the once-per-session `hasResetHoverBindModeThisSession` flag
  - on a first profile-era login, get copied into `ACABProfilesDB["Default"]`
- **Verify:** Temporarily print `event` + `ACAB.activeProfileName` at the top of the Events.lua handler, then `/reload` and log in fresh. Any `prof=nil` line confirms it. Fix: gate on `ACAB.activeProfileName` or on login-sequence completion.

### Profile deleted on another character is silently recreated with defaults
- **Where:** `Database.lua` — `ACAB:ResolveActiveProfile`
- **What:** Char B's `ACABCharDB.activeProfile` names a profile char A deleted. `ACABDB` becomes nil, `EnsureDB` builds fresh defaults, and `activeProfileName` keeps the deleted name. Logout's `SaveActiveProfileData` then resurrects the profile with defaults, and char B loses its layout instead of falling back to Default.
- **Verify:** Create "X" on A, switch B to "X", delete "X" on A, log into B. `/run print(AlternativeClassicActionBars.activeProfileName)` → `X`. After logout, `/acab profile list` shows "X" again.

### Hoverbind SaveBindings can persist other buttons' session-only swap redirects
- **Where:** `HoverBind.lua` — `ApplyHoverBindKey` / `ClearHoverBindKey`, `SyncDefaultBarBindingRedirect`
- **What:** During a stance/page swap, `SyncDefaultBarBindingRedirect` moves a default-bar button's key from its native action (`ACTIONBUTTON1`) to `ACABBIND<n>`, unsaved on purpose. Hoverbind only rehomes the *hovered* button before `SaveBindings(...)`, so every other redirected button's `ACABBIND<n>` binding gets saved too. After relogging in a non-swapped state, the native action stays unbound. Blizzard's Key Bindings "Okay" does the same.
- **Verify:** Assign an Extra Bar as a stance source for bar 1. Enter that stance, hoverbind any *other* button, `/reload` in caster form. `GetBindingKey("ACTIONBUTTON1")` nil + key on `ACABBIND<n>` confirms it. Fix: rehome all default-bar buttons before any SaveBindings, then re-sync.

### Slot allocator reserves cols*rows slots, but a bar's pool binds all 12
- **Where:** `Bar.lua` — `IsActionSlotUsed`, `ApplyBarShape` / `ResolvePoolSlot`
- **What:** The allocator counts a bar as `slotStart .. slotStart + cols*rows - 1`. Every one of the `MAX_BAR_BUTTONS` pool buttons (hidden ones too) binds `slotStart + i - 1` and registers in `customBindTargets`. A shrunk bar plus a later-seeded Extra Bar can overlap. Low impact, since Extra Bars normally seed once.
- **Verify:** `/run local c=ACABDB.bars for i=1,table.getn(c) do DEFAULT_CHAT_FRAME:AddMessage(c[i].id.." "..tostring(c[i].slotStart).." "..(c[i].cols*c[i].rows)) end`. Two slotStarts less than 12 apart confirm an overlap. Fix: count `MAX_BAR_BUTTONS` for pool-backed bars.

### Pet/Stance Bar page can be the wrong kind after a runtime native-mode flip
- **Where:** `SettingsBars.lua` — `UsesSimpleBarPage` / `GetOrCreateBarPage` / `GetOrCreateSimpleBarPage`; trigger `ResetAllElementsToVanillaLayout`
- **What:** The styled (full) and native (simple) Pet/Stance pages share one cache key (`settingsFrame.pages[PET_BAR_ID]`). Force Vanilla Layout Mode sets `useNativePetBar/useNativeStanceBar = true` without a reload. An already-built styled page is then refreshed as the native page: stale Button Size/Spacing/Grid controls, and X/Y driven by the native container.
- **Verify:** On a non-Default profile with styled Pet Bar, open its page, turn Force Vanilla Layout on, reopen the page. `/run local A=AlternativeClassicActionBars local p=A.settingsFrame.pages[A.PET_BAR_ID] DEFAULT_CHAT_FRAME:AddMessage(tostring(p and p.buttonSizeSlider~=nil))` prints `true` if stale. Fix: separate cache keys, or drop the page when the flag flips.

### Color picker never sets `ColorPickerFrame.previousValues`
- **Where:** `UIWidgets.lua` — `ACAB:OpenColorPicker` (used by Setup Wizard step 7 and the Experience Bar settings page)
- **What:** A `cancelFunc(previousValues)` is installed, but `ColorPickerFrame.previousValues` is never assigned before `ShowUIPanel`. Vanilla's Cancel passes that field through, so Cancel restores nothing, or restores another addon's stale value.
- **Verify:** Open a swatch, drag to a very different color, click Cancel. Swatch keeps the new color → confirmed. Also `/run DEFAULT_CHAT_FRAME:AddMessage(tostring(ColorPickerFrame.previousValues))` while the picker is open. Fix (one line, covers both callers): `ColorPickerFrame.previousValues = { r = current.r, g = current.g, b = current.b }` before `ShowUIPanel`.

### Wizard slider readouts can stay blank on first open (cosmetic)
- **Where:** `SetupWizard.lua` — `ACABSetupWizardMixin:Reset` (step 7 font size / pulse interval, step 8 spacing/size)
- **What:** `Reset` sets these sliders via `ACAB:SetSliderValueSilently(slider, value)` without readout text, relying on `OnValueChanged` to write it. `SetValue` with an unchanged value doesn't fire, and a new slider starts at its min. So a saved value equal to the min (font size 6, pulse 0.5) leaves the readout empty.
- **Verify:** Set Rested Glow Pulse Interval to 0.5, `/reload`, run the Setup Wizard to step 7 and enable Better Experience Bar. A blank readout confirms it. Fix: pass `valueText` + formatted text to `SetSliderValueSilently`.

### Wizard always writes global spacing/button size, even on paths that never show step 8
- **Where:** `SetupWizard.lua` — `ApplyWizardStateToProfileData`
- **What:** `globalSpacingEnabled`/`globalButtonSizeEnabled` are written behind `~= nil` gates, but `Reset` seeds them `false`, so the gate always passes. Finishing early (step 2 "Lock down" or step 5 "Keep Vanilla Layout") turns off a profile's existing global spacing/size. `modernBorderStyle` is seeded `nil` and handled correctly. **May be intended**, since the overwrite dialog says it overwrites "global spacing/size". Ask the owner.
- **Verify:** Enable global spacing on a non-Default profile, run the wizard in overwrite mode, pick "Keep Vanilla Layout". After the reload, `/run DEFAULT_CHAT_FRAME:AddMessage(tostring(ACABDB.globalSpacingEnabled))` → `false` confirms.

### Global spacing readout can exceed the slider's max after a border-style switch
- **Where:** `SettingsGeneral.lua` — `RefreshGeneralPanel`
- **What:** `globalSpacingValue` is stored in displayed units; its max is 20 in modern style and 16 in vanilla style. Switching to vanilla with 20 saved clamps the thumb to 16, but the readout says "20" and `ApplyGlobalSpacingToBar` applies 20 + 4 = 24 real spacing, above `SPACING_MAX`.
- **Verify:** With modern style on and global spacing at 20, uncheck "Use Modern Button Style". Readout still says 20. `/run print(ACABDB.globalSpacingValue)` → `20`.

### ApplyModernSingleVerticalBar(5) and the cluster layout disagree when bar 4 has no rect
- **Where:** `DefaultBars.lua` — `ApplyModernSingleVerticalBar` vs `ApplyModernVerticalBarClusterLayout`
- **What:**
  - Bar 5's single Modern reset returns early when bar 4's `GetElementRealEdges` left is nil, after already writing buttonSize/spacing. Bar 5 is left unmoved and unenabled. The wizard's cluster layout falls back to `cfg4.x` instead.
  - Neither path calls `SetBarLayout(bar, 1, 12)` for bars 4/5, so a custom grid survives a Modern reset.
- **Verify:** With bar 4 disabled, `/run local A=AlternativeClassicActionBars;print(A:GetElementRealEdges(A.bars[4]))`. `nil` means the early return is reachable. Then press bar 5's "Reset to Modern Layout Default".

### GameTooltip keeps the custom Tooltip scale for widget-anchored tooltips
- **Where:** `NativeElements.lua` — `HookGameTooltipDefaultAnchor`
- **What:** The `GameTooltip_SetDefaultAnchor` hook sets `GameTooltip:SetScale(ACABDB.tooltipScale)`, and nothing resets it. `SetOwner(this, "ANCHOR_RIGHT")` tooltips (action buttons, settings widgets, minimap) never go through SetDefaultAnchor, so they probably keep the last custom scale. Same after disabling the Tooltip element, until reload.
- **Verify:** Tooltip scale 1.5, hover an NPC, then an action button. `/run print(GameTooltip:GetScale())`.

### Stance Bar rebuild relies on UPDATE_SHAPESHIFT_FORMS, which may never fire here
- **Where:** `Events.lua` — `stanceFormEventFrame`; `PetStanceBars.lua` — `RebuildStanceBarContainer`
- **What:** The only runtime trigger for `RebuildStanceBarContainer` / `ApplyStanceBarLiveShape` / `RebuildAllDefaultBarAssignmentRows` is `UPDATE_SHAPESHIFT_FORMS`. §5aj confirmed it doesn't fire on form *toggles*; nobody has tested whether it fires when the set of forms *changes*. If it doesn't, a newly learned form or a respec won't reshape the Stance Bar until `/reload`. A class with no forms at login never builds the container. Keep the registration regardless.
- **Verify:** On a low-level druid/warrior, learn a new form/stance and watch for the button without `/reload`. Or trace `UPDATE_SHAPESHIFT_FORMS` + `SPELLS_CHANGED` / `LEARNED_SPELL_IN_TAB`.

### Page Indicator: an unmoved click can drop follow mode when snapping is on
- **Where:** `NativeElements.lua` — `StartPageIndicatorDrag` / `StopPageIndicatorDrag`
- **What:** Stop restores follow mode only if `pos.x/pos.y` exactly equal the start values. Every drag tick runs `ApplyDragSnap`, so with snap-to-grid (center-lock every tick) a no-move click can still shift `pos`, and follow mode turns off.
- **Verify:** With Edit Layout + snap-to-grid on and the indicator following Main Bar, click it without moving, then move Main Bar.

### Main Bar art-dropdown pulse sequences overlap on repeated clicks (cosmetic)
- **Where:** `SettingsBars.lua` — `ACAB:HighlightMainBarArtModeDropdown`
- **What:** Each call schedules five uncancelled `C_Timer.After` Show/Hide steps over ~2 s. A second click during a pulse interleaves two sequences and flickers. Fix: a per-strip generation counter checked by each timer.

---

## 2. Client quirks (how this client behaves, and where the code relies on it)

### Lua / runtime
- **`string.match` is available despite being Lua 5.1.** `Core.lua`'s slash dispatcher / `HandleProfileCommand` rely on it, and it works live. Presumably one of the client mods supplies it. Don't "fix" it to `string.find` captures. Check: `/run print(string.match, string.gmatch)`.
- **`X and X(...)` truncates a multi-return call to one value** (stock Lua, §5ah). Capture multi-return APIs (`GetPetActionInfo`: 7 values incl. `subtext` in position 2) inside a real `if X then ... end` block.
- **Lua 5.0 caps each function at 32 upvalues.** The local `luac` (5.1) allows 60 and won't catch it. Watch big settings builders when adding file-level locals; `SettingsBars.lua` peaks around 18.
- **Global `_` is written by pet-slot captures** in `Button.lua` `ACABButtonMixin:Refresh` / `OnEnter` (`name, _, texture, ...` with no `local _`). Harmless so far. Declaring `local _` there is a behavior-scoped change.

### Frames, rects and layout
- **Lazy, top-down rect resolution (§5af).** A child read before its ancestor caches a stale rect. Discarded ancestor reads before child reads are load-bearing in:
  - `Settings.lua` `ApplySettingsHeightFromCandidates` (see §3)
  - `DefaultBars.lua` `WarmMainBarArtAncestorChain` / `GetButton1ScreenAnchor` / `ResolveNativeTopLeft`
  - `NativeElements.lua` Page Indicator (`UIParent:GetLeft(); container:GetLeft()` before `RealRect`)
- **No rect until sized (§5ak).** A frame with only `SetPoint` returns nil rects forever. Placeholder `SetWidth(1)/SetHeight(1)` at creation is load-bearing (Page Indicator container, `Settings.lua` bar-list scroll child). `MainMenuBarArtFrame` needs its native width/height re-asserted on every `ApplyMainBarArtPosition` (order: size → scale → ClearAllPoints → SetPoint).
- **Same-name `CreateFrame` makes a second frame (§5ag).** Per-rebuild name counters in `SettingsBars.lua` (`RebuildDefaultBarAssignmentRows`, `RefreshBarList`) are load-bearing. The Setup Wizard uses fixed names and is only safe because it's a build-once singleton: if steps ever get rebuilt, suffix a counter on every name.
- **ScrollFrame must stay paired with its original scroll child** (`Settings.lua` `CreateSettingsFrame`, `CreateWideContentScrollFrame`). Pointing a ScrollFrame at a new child leaves that child unresolvable. Build a new pair instead.
- **FontString anchored only by TOPLEFT+TOPRIGHT won't wrap.** Set an explicit `SetWidth` before `SetText`, then read `GetHeight` (`Settings.lua` `SetProfileLockBannerMessage`).
- **Strata survives reparenting.** ActionBarUp/DownButton keep `MainMenuBarArtFrame`'s MEDIUM strata after `SetParent`. `NativeElements.lua` `ApplyPageIndicatorStrata` reasserts HIGH + explicit levels on every apply. Bars (`Bar.lua` `ApplyBarShape`) re-set HIGH/level 10 on every shape pass, because page/stance swaps or `MainMenuBarArtFrame:Raise()` otherwise bury Bar 1 (§5ae).
- **Edit-mode overlays are parented to UIParent** (`DefaultBars.lua` `EnsureContainerOverlay`) so all overlays compare FrameLevel in one tree. Hiding an element never hides its overlay: every disable path must `overlay:Hide()` + `EnableMouse(false)` itself. Overlapping overlays need distinct explicit levels (Key Ring 150 vs default 100).
- **Page Indicator is laid out from `GetPoint` data, not rect deltas** (`NativeElements.lua` `CreatePageIndicatorContainer` / `ApplyPageIndicatorShape`). Right after login, sibling rects can still be cached from before the art moved. `MainMenuBarPageNumber` (FontString) has no `GetEffectiveScale`, so `ACAB:PixelSetPoint` falls back to plain `SetPoint`.
- **Latency Bar Modern reset measures one frame late** (`NativeElements.lua` `ResetLatencyBarLayoutToModernBase`). Overlay rects don't reflect `SetScale(1)` until the next frame. `ApplyModernCornerClusterLayout` takes every measurement before any `Apply*Position`.
- **Simple-page reset refresh is deferred one frame** (`SettingsBars.lua` `CreateSimpleBarPage`), because the element's new size resolves next frame. It uses `ACAB:DeferFit`. If `DeferFit` ever starts coalescing, these need their own next-frame helper.

### Native frames and FrameXML
- **Native code re-anchors wrapped frames without `ClearAllPoints`**: Key Ring, Latency Bar, Micro Menu and Bag Bar buttons (`MainMenuBarBackpackButton`, `QuestLogMicroButton` seen), the art frame. `DefaultBars.lua` `InstallReanchorGuard` swallows every unflagged `SetPoint`/`ClearAllPoints` and records the last swallowed anchor in `frame.ACABSwallowedAnchor`, which `Core.lua` `WaitForWrappedFrameAnchorSettle` polls. Every own re-anchor must set the element's guard flag around it. `relativeTo` can arrive as a name string, and indexing a string errors, so check for the string first. `ApplyGridAnchoredShape` hard-codes `ACABApplyingMicroMenuPosition`: fine while Micro Menu is the only grid container.
- **`ShapeshiftBar_Update` checks `MultiBarBottomLeft:IsShown()`** to pick Stance Bar border art. `DefaultBars.lua` `ForceShowMultiBarBottomLeft` force-shows it with `Hide` neutered, then re-runs `ShapeshiftBar_Update()` once. Don't clean either up.
- **Stance assignment keys off the active form, not the action page** (`DefaultBars.lua` `GetDefaultBarSlotForIndex`). Travel/Aquatic Form leave the page at 1. `GetShapeshiftForm()` returns nil here, so use `GetShapeshiftFormInfo`'s `isActive` (§5aj).
- **`ShapeshiftButton` backdrop must be a separate frame** (`PetStanceBars.lua` `ApplyStanceBarBorderStyle`). `SetBackdrop` on the real button draws over the icon and greys it out.
- **`SHOW_MULTI_ACTIONBAR_1-4` don't survive logout (§5m).** `Database.lua` `SeedOneDefaultBar` seeds `enabled` from `DEFAULT_BAR_GRID`.
- **Edit mode's Escape exit is a keybinding swap** (`Core.lua` `ACAB_EditModeEscapeFire` / `Enable/DisableEditModeEscapeBinding`). An `EnableKeyboard(true)` capture frame blocks every other key on this client. So `ESCAPE` is bound to `ACABEDITMODEESCAPE` (bindings.xml → plain global), never saved, and reverts on reload. Don't add `SaveBindings` here; keep the global.
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

### Experience Bar (§5x–§5ad)
- **Region map:**
  - `MainMenuExpBar` is a StatusBar.
  - `ExhaustionLevelFillBar` is a **Texture** (use `Set/GetVertexColor`; `SetStatusBarColor` silently no-ops).
  - `MainMenuExpText` doesn't exist. The native XP label is a FontString region of `MainMenuBarOverlayFrame`, found by `GetObjectType()`.
  - Border art is `MainMenuXPBarTexture0-3`.
- **Native XP label re-shows itself.** `ApplyBetterExpBarVisual` neuters its `Show` while Better Experience Bar is on, capturing the real `Show` once, before the first neuter.
- **Bottom border is a gradient strip, final** (`EnsureExpBarBottomBorderStrip`). Two native-art clone attempts rendered distorted. Don't retry without a live tex-coord dump.
- **Text overlay must be a HIGH-strata child of `MainMenuExpBar`** (`EnsureExpBarTextOverlay`). Parented to UIParent it measured 0.9× the bar and drifted.
- **Rested tick texture paths must use the installed folder name** `Interface\AddOns\AlternativeClassicActionBars\...`. A wrong segment renders a blank tick silently.
- **`GetRestState() == 1`** (banked rested XP) gates the rested overlay; **`IsResting() == 1`** (in a rest area now) gates only the glow/pulse. Don't swap them. `GetFont()` sizes come back as floats, so round them.

---

## 3. Fragile orderings (code that must stay exactly as written)

### Settings height-fit top-down resolve pass
- **Where:** `Settings.lua` — `ApplySettingsHeightFromCandidates`
- **What:** After `SetVerticalScroll(0)` it does `scrollChildPanel:GetTop()`, then `GetBottom()` on every candidate, then `GetBottom()` on the General panel's static anchor chain, all discarded. This is the §5af fix, and three "equivalent" rewrites all brought the bug back.
- **Keep:** the block byte-for-byte, including the per-call `resolveNames` table and loop order. A new General-tab control hanging off an unmeasured static anchor needs that anchor added to `resolveNames`. Symptom if broken: toggling Global Spacing makes the controls below it unreachable.
- **Related:** `MeasureDeepestExtent` must stay a live-position delta (`referenceTop - frame:GetBottom()`), since the window is movable. The `Fit*` candidate lists feed this pass in order: any conversion to name tables must produce an identical array.

### Inline dropdown SetParent after CreateFrame
- **Where:** `UIWidgets.lua` — `ACAB:CreateInlineDropdown`
- **What:** The explicit `SetParent(parent)` right after `CreateFrame(..., parent, ...)` is most likely a no-op (§5ag says a reused name makes a new frame, not a reparented old one). It's kept because removing it is risk with no gain. The `OnShow` handler that reapplies `UIDropDownMenu_SetWidth`/`SetText` **is** load-bearing: dropdowns built while hidden otherwise render with a fragmented skin and a blank label.

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
  - `DefaultBars.lua`: `ACAB:ResetScaleAndResolveNative` (Latency/Cast/Exp Bar)
  - `NativeElements.lua`: `ResetKeyRingPosition`, `ResetTooltipLayout`
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
- **Export format is byte-stable** (`TBVPROFILE1:`). Never add whitespace to `SerializeValue`, or older parsers reject it. The parser doesn't trim bare tokens (`[1]=false }` fails), and numbers round-trip at 14 significant digits.

### FinishWizard's live-profile switch orderings
- **Where:** `SetupWizard.lua` — `FinishWizard`, `ApplyWizardStateToProfileData`, `ApplyGeneralLayoutFormat`
- **Order:** ApplyWizardStateToProfileData → SaveActiveProfileData (old) → switch `ACABDB` → re-point every `ACAB.bars[id].config` via `GetBarConfig` → ApplyGeneralLayoutFormat → `ACABCharDB` → SaveActiveProfileData → ReloadUI.
- **Why each step matters:**
  - `lastAppliedVanillaStyle` must be set together with `modernBorderStyle`, or the next login is treated as a live style switch.
  - `ResetAllElementsToVanillaLayout` forces swap back on, so the wizard's swap choices are re-applied after it.
  - The Exp Bar position is written before `ApplyModernLayoutGeometry`, because `DefaultBars.lua` `GetModernBaseExpBarClearance` reads the saved position, not the live frame.

### Wizard layout invariants
- **Where:** `SetupWizard.lua` — `CreateWizardNavButton`, `MeasureStepBottom`, `NormalizeAnchorToTopLeft`, `FitHeightToStep`
- **What:**
  - Next/Finish carry `ACABNavButton = true` and are skipped by `MeasureStepBottom`. Counting them caused a grow-every-fit feedback loop.
  - The wizard stays TOP-anchored.
  - `NormalizeAnchorToTopLeft` runs only on drag end (`GetTop()` after `ClearAllPoints`/`SetPoint` is stale).
  - Step content anchors to `step` at computed offsets, never to siblings that get hidden.

### Pool-button construction order
- **Where:** `Button.lua` — `ACABButtonMixin:Init`
- **What:**
  - `equipRing` exists before `ApplySize`.
  - Native font capture runs after the `hotkey`/`count` FontStrings exist and before their `SetFont`.
  - The reparented `PetActionButton<n>AutoCast` Model must never get `SetModel()` again, which resets it to a white plane (resize via `SetModelScale`).
  - Button and cooldown set HIGH strata explicitly.
  - `ApplyBorderStyle` shares the `Init` helpers, so new border pieces go there.

### Removed intra-addon existence guards
- **Where:** `Bar.lua`, `Button.lua`, `HoverBind.lua` (removed in the refactor); `Core.lua`/`Events.lua` still have some
- **What:** Guards like `if ACAB.RefreshBarSettingsPage then` were dropped because every guarded member is defined at the top level of a file that always loads, and every call runs after login. So:
  - Nothing may call `CreateActionButton` / `ApplyEditModeVisual` / `ApplyGlobalButtonStyle` / `ApplyHoverOnlyState` at file-load time.
  - `HoverBind.lua`'s top-level `customBindTargets = {}` must run before any button is created.
  - `Core.lua`'s hover-fade code calls `ACAB:GetCursorPositionUIScale` (defined later, in DefaultBars.lua): runtime-only.

### Shared single-frame element helpers
- **Where:** `DefaultBars.lua` — "Single-frame element helpers" section: `SetElementShown`, `WriteSavedPositionXY`, `StoreCompensatedScale`, `ResetScaleAndResolveNative`, `ReadNativeAnchor`, `SeedNativePosition`, `CopyNativePosition`
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
- **Stance gap capture before bars.** `PetStanceBars.lua` `CaptureStanceBarNativeGap` runs in the login sequence before `CreateFixedSlotDefaultBars`, which collapses the native anchor. (The value itself is dead, see §4.)
- **Setup Wizard reads saved Exp Bar position.** `DefaultBars.lua` `GetModernBaseExpBarClearance` must read the saved Exp Bar position, not a live rect.
- **Exp Bar layered under Latency Bar.** `ExperienceBar.lua` `ApplyExpBarPosition` copies Latency Bar's strata at level −1. This interacts with `MainMenuBarArtFrame`'s pinned MEDIUM/level-5 masking (§5ae), so change both together.
- **Wheel resize.** `Bar.lua` `ACAB:ResizeBarFromWheel` is shared by the bar overlay and the button handler. The button's wheel handler must stay installed, since it swallows camera zoom over buttons outside edit mode.
- **Login timing.** The settle polls (`Core.lua` `WaitForNativeBarSettle`, `WaitForWrappedFrameAnchorSettle`, `WaitForPostLoginSettleThenVerify`) are load-bearing: `stableCount` resets on any mismatch/nil, the check runs after `elapsed++`, and only a timeout without settling warns. Test any change with `/reload` and a fresh login.

---

## 4. Tech debt & cleanup candidates

### Dead code kept on purpose (would change saved data or chat output)
- **`stanceBarNativeGap`.** `PetStanceBars.lua` `CaptureStanceBarNativeGap` and `ACABDB.stanceBarNativeGap` are captured but never used for layout (`GetStanceBarBaselineY` uses fixed `PET_BAR_NATIVE_GAP`). Removing them changes a WARNING print and saved data. Remove together: the capture, its two call sites, and the EnsureDB self-heal.
- **Legacy profile fields.** The reserved "ModernBase" profile name (`Database.lua` `MODERN_BASE_PROFILE_NAME`) is legacy but still hides old `ACABProfilesDB["ModernBase"]` entries. `disableBlizzardArt`, `mainBarPaginationEnabled`, `mainBarStanceSwapEnabled`, `mainBarPageBarAssignment` and `mainBarStanceBarAssignment` stay in saves forever. Cleaning up needs a one-shot migration.
- **`RunLoginSequence` params.** `Core.lua` `ACAB:RunLoginSequence(earlyLeft, earlyTop, settledLeft, settledTop, waited)` reads none of its parameters.
- **`Button.lua` stubs.** The stance tooltip fallback for missing `GameTooltip.SetShapeshift` never runs, stock-API guards never fail, and `OnDragStop` is empty.
- **C_Timer hedges.** `Settings.lua` `DeferFit` and `SettingsGeneral.lua` `HighlightGeneralLayoutCheckbox` check for `C_Timer`. ClassicAPI is a hard dependency, and `DeferFit`'s synchronous fallback would bring back the stale-rect bug.
- **Redundant guards.** `Core.lua` (`ApplyHoverBindVisual`, `GetBarFrameSize`) and `Events.lua` (`RefreshBarSettingsPage`, `RebuildAllDefaultBarAssignmentRows`) still guard members that are always defined.

### Tech debt
- **Native anchor capture skipped when a position exists.** `NativeElements.lua` `Capture{KeyRing,LatencyBar,CastBar}PositionIfNeeded` return early before capturing `*NativeAnchor`. A writer that sets the position first (Modern corner cluster, import) leaves the native anchor nil forever, and the Vanilla reset then silently no-ops. Check: `/run print(ACABDB.keyRingNativeAnchor, ACABDB.latencyBarNativeAnchor, ACABDB.castBarNativeAnchor)`.
- **Pet Bar reflow rewrites `cfg.nativeAnchor.y`.** `PetStanceBars.lua` `ReflowPetBarForBar3Toggle` does this, so treat the Pet Bar `nativeAnchor` as "last default-stack position", not the true capture.
- **Page Indicator retry chains can stack.** Parallel `C_Timer.After(0.1)` retry chains in `CreatePageIndicatorContainer` / `ApplyPageIndicatorShape` share one elapsed counter. Harmless so far; a "retry pending" flag would bound it.
- **Extra Bar fallback size.** `Database.lua` `GetDefaultExtraBarLayout` returns `BUTTON_SIZE` on the normal path but `GetCurrentButtonSizeBaseline()` on the fallback path.
- **Two screen-size reads.** `Settings.lua` `GetScreenCoordinateRange` and `Bar.lua` `RebuildLayoutGrid` use `UIParent:GetWidth()/GetHeight()` instead of `GetUIParentAnchorSize`. It's harmless in both today (legacy range only / covered by overshoot lines). In `RebuildLayoutGrid`, `GetLayoutGridSpacing()` is already in local units, so don't divide it by effective scale.
- **Wizard config drift.** `SetupWizard.lua` steps 6–8 hand-copy labels, slider ranges, default colors and the exp-bar text-toggle list from the settings pages. Grep the wizard whenever you change one of those.
- **Sidebar rows follow `getElementFrame`.** `SettingsBars.lua` `RefreshBarList` shows a simple-page row only when its config's `getElementFrame()` is non-nil. New simple pages need a `getElementFrame`.
- **Composed names hide greppable identifiers.** The Pet/Stance "Use Vanilla" checkbox name and field are built by concatenation (`CreateUseVanillaBarCheckbox`). Grep the factory name.

### Performance (measured as fine so far; look here first if something stutters)
- **Settings frame leak.** `SettingsBars.lua` `RebuildGridSwatches`, `RefreshBarList` and `RebuildDefaultBarAssignmentRows` make new frames on every rebuild and only hide the old ones. Check `gcinfo()` before/after opening the Stance page ~50 times. Pooling with names unique per pool slot would bound it without reintroducing §5ag.
- **Hover-bind ticker allocation.** `HoverBind.lua`'s ticker builds a ref table per visible button every 0.25 s while hoverbind mode is on.
- **Range ticker writes.** `Button.lua`'s shared range ticker calls `IsSlotFilled` three times per button and does unconditional `Show`/`Hide`/color writes every 0.2 s. It's the hottest path in the addon; caching the last state per button would cut it.
- **Pet Bar re-layout.** `Button.lua` `Refresh` on a pet slot re-lays out the whole Pet Bar, so one `PET_BAR_UPDATE` means 10 full layouts.
- **Main Bar drag.** Every tick re-applies the art frame (texture Hide/Show redraw, which is load-bearing) plus all grouped elements, each with a fresh hover closure.
- **Rested-glow pulse.** `ExperienceBar.lua`'s 20 Hz pulse ticker keeps running while the Exp Bar is disabled.

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
- **Assignment-row stance count.** `SettingsBars.lua` `RebuildDefaultBarAssignmentRows` is the only live stance-count read without the `MAX_STANCE_BUTTONS` clamp, so it doesn't use `GetClampedLiveStanceCount`. It only differs above 10 forms.
- **Default-bar overlays.** `DefaultBars.lua`'s own overlays have wheel handlers similar to `ACAB:ResizeBarFromWheel`.

### Decomposition ideas (need `.toc` + CLAUDE.md updates)
- **`DefaultBars.lua`** holds three subsystems: default-bar paging / Modern geometry, Main Bar art + grouped elements, and the shared drag / container / guard engine. Move the engine to its own file loaded before `DefaultBars.lua`, keeping the top-level `InstallReanchorGuard(MainMenuBarArtFrame, ...)` after it.
- **`SettingsBars.lua`** (~3800 lines): the simple-page subsystem is ~1100 self-contained lines. The Force-Vanilla cascade isn't UI code. Shared `CreateReflow*` locals would need to become `ACAB:` methods first, which also helps the upvalue cap.
- **`NativeElements.lua`**: Tooltip and Page Indicator could become their own files.
- **`Database.lua`**: the serializer/parser could become `ProfileIO.lua`, and the first-login/create-profile dialogs are UI.
- **`SetupWizard.lua`**: the preview builders and the apply/finish logic are separable.
- **`UIWidgets.lua`**: `ACABDialogMixin` is the largest self-contained unit.
- **`Bar.lua`**: the layout-grid overlay and the Extra Bar policy are separable.
