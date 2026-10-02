# Mistakes Log

Solved mistakes, so they don't happen twice. Each entry has three parts: **what happened**, the **root cause**, and how to **prevent** it. Add new entries at the end of the matching section. Client facts live in `docs/01-Environment-Capability-Analysis.md` (`env §N`); code-level gotchas live in `docs/known-problems.md`.

---

## Process

### Guessing instead of checking live
- **What happened:** frame names (`MainMenuExpText`), widget types (`ExhaustionLevelFillBar` as a StatusBar), API behavior (`SetPetAction` handling token slots) and anchor offsets (button border at 0,0) were written from retail/FrameXML memory. Each one shipped broken, sometimes for several rounds.
- **Root cause:** retail and stock-1.12 knowledge treated as fact for this modded client. Defensive `getglobal` checks turned a wrong guess into a silent no-op instead of an error.
- **Prevention:** before relying on an unconfirmed name, type, signature or offset, hand the user a `/run` check (≤ 261 chars including `/run `) and wait for the result. A guard that hides failure is not verification.

### Speculating with agents instead of asking for a `/run`
- **What happened:** agents were sent to reason about live client state that a one-line `/run` would have answered.
- **Root cause:** code reading can't see runtime state.
- **Prevention:** for anything about live values, ask the user for a quick `/run` check first.

### Rewriting "debug-only" code that flipped behavior
- **What happened:** the Settings height-fit bug (controls below Global Spacing unreachable) took nine live rounds. Three "clean equivalents" of a working diagnostic block all brought the bug back.
- **Root cause:** each rewrite dropped a detail that mattered (a leading parent read, the read order). The discarded reads were the fix (env §4.6).
- **Prevention:** when removing "only debug prints" changes behavior, restore the working text byte for byte and bisect one variable at a time.

### Over-reading binary string tables
- **What happened:** `issecurevalue`, `issecurevariable`, `scrubsecurecall`, `securecallfunction`, `secureexecuterange` and `pcallwithenv` were documented as available. All are `nil` live.
- **Root cause:** a list of names near real natives was read as one registration list. Only names with their own `Usage:` string were real.
- **Prevention:** treat static string finds as hypotheses until a live `type(x)` check confirms them.

### Retail architecture assumed
- **What happened:** the first design planned `SecureActionButtonTemplate`/`SecureHandler*` buttons and `InCombatLockdown()` gating.
- **Root cause:** none of that exists on 1.12. `InCombatLockdown()` always returns `false` (env §4.1).
- **Prevention:** check env §3/§4 before designing around any retail system. Use action slots 73–120, and use `PLAYER_REGEN_*` for combat state.

### Declaring one root cause closed too early
- **What happened:** the default-bar anchor bug was declared "scale, not timing" once the scale fix landed. A separate `PLAYER_LOGIN` timing bug in the same code resurfaced right after.
- **Root cause:** one real fix was taken as proof that no other cause existed.
- **Prevention:** after a fix, re-run the original live check. Don't write "X was never the problem" without data that rules X out.

### Chasing native look as an addon bug
- **What happened:** a "diagonal gap" between the Main Bar button border and the art was investigated as our bug.
- **Root cause:** vanilla itself looks like that. The user confirmed it with the addon disabled.
- **Prevention:** compare against the client with the addon disabled before debugging a visual mismatch.

### Wrong `/run` length limit
- **What happened:** diagnostics were written for a 511-character `/run` limit.
- **Root cause:** an unverified figure. The live limit is 261 characters total.
- **Prevention:** count the full command, `/run ` included. Anything longer goes into a temporary `/acab diagN`.

### Live check that didn't reproduce the native call
- **What happened:** a `/run` calling `ExhaustionTick_Update()` showed no repaint, and another used the global `ACAB`, which doesn't exist (the global is `AlternativeClassicActionBars`). One test also left `event` set and broke chat.
- **Root cause:** native handlers read the global `event`/`this`; `ACAB` is only a file-local alias.
- **Prevention:** set and restore `this`/`event` around native handler calls, and use the full global name in `/run`. Ask which run a result came from before drawing conclusions.

---

## Saved data and login

### Capturing native positions without scale conversion
- **What happened:** the captured `nativeAnchor.x` (178.67) didn't match `ActionButton1:GetLeft()` (254.52).
- **Root cause:** `GetLeft()` is in the queried frame's effective-scale units, and it was stored as a UIParent offset unconverted.
- **Prevention:** convert with `value * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()` whenever a coordinate crosses frames (env §4.6).

### Capturing at `PLAYER_LOGIN`
- **What happened:** default bars seeded ~76 px left of the real Blizzard position.
- **Root cause:** `MainMenuBar` re-centers after `PLAYER_LOGIN`. Every recapture ran at the same too-early moment.
- **Prevention:** capture after `PLAYER_ENTERING_WORLD` plus a settle poll (`WaitForNativeBarSettle`).

### Copying a stale profile snapshot
- **What happened:** unlocked Vanilla wizard profiles put every action bar ~76 px left on a fresh install.
- **Root cause:** the wizard copied `ACABProfilesDB["Default Vanilla"]`, which still held the first-login anchor (178). The same login's recapture had only fixed the live `ACABDB` (254). Profiles with `useDefaultLayout == false` skip the drift check, so they never healed.
- **Prevention:** when the source profile is the active one, save live data before copying it (`GetDefaultVanillaData`). Before this was found, a guessed cause (the stance event handler) was patched and disproved. Trace the data path with `DIAG` lines first.

### One-shot markers used to force a watched recapture
- **What happened:** five successive one-shot markers "never fired" in the user's pasted log.
- **Root cause:** `ACABDB` is account-wide. Any earlier login or reload on any character consumed each marker before the user watched.
- **Prevention:** use an explicit command (`/acab recapture`) for anything the user needs to observe. Markers are for silent migrations only.

### Trusting `SHOW_MULTI_ACTIONBAR_1-4` across logout
- **What happened:** enabled bars 2–5 survived `/reload` but reset after a real logout.
- **Root cause:** those globals don't persist on this fork. Login reconciliation read them as truth.
- **Prevention:** the addon's own saved flag is the source of truth. Native globals are only for same-session reads (env §4.5).

### Guessing CVar names
- **What happened:** Lock Action Bars sync tried candidate CVar names.
- **Root cause:** `GetCVar` throws on unknown names, and the setting isn't a CVar at all: it's the global `LOCK_ACTIONBAR` (`"1"`/`"0"`).
- **Prevention:** never probe CVar names. Confirm the storage live first.

### Events firing before the profile loaded
- **What happened:** early XP/rest events on login touched settings before the profile existed, with errors on fresh installs.
- **Root cause:** always-registered event frames ran before `RunLoginSequence` resolved the profile.
- **Prevention:** addon-wide event handlers no-op until `ACAB.activeProfileName` is set.

### Slot allocator counting visible slots only
- **What happened:** Extra Bars' action slots overlapped after a bar was shrunk.
- **Root cause:** the allocator reserved `cols*rows` slots, but every bar's pool binds all 12.
- **Prevention:** reserve the full `MAX_BAR_BUTTONS` block per pool-backed bar.

---

## Native frames re-asserting themselves

### Latency Bar / Key Ring drifting after combat, looting or zoning
- **What happened:** wrapped native frames moved back on their own, sometimes without user input.
- **Root cause:** positions were applied once. Native FrameXML re-anchors those frames later, without `ClearAllPoints`.
- **Prevention:** wrap every native frame we position with `InstallReanchorGuard`, and reassert on `PLAYER_REGEN_ENABLED`/`LOOT_CLOSED`. Assume native code will undo any one-time change to a native frame.

### Disabled Experience Bar reappearing
- **What happened:** after the user disabled it, the Exp Bar came back on quest turn-in, level-up and XP updates.
- **Root cause:** native code calls `MainMenuExpBar:Show()` on those events.
- **Prevention:** `InstallShowGuard` on the frame. The native XP label needs the same treatment (its `Show` is neutered while Better Experience Bar is on).

### Better Experience Bar colors resetting to blue
- **What happened:** after some time, or on a zone change, the custom earned-XP color turned blue (`0, 0.39, 0.88`), which is not the addon default either.
- **Root cause:** FrameXML's `ExhaustionTick_OnEvent` repaints `MainMenuExpBar` and `ExhaustionLevelFillBar` on `PLAYER_ENTERING_WORLD`/`UPDATE_EXHAUSTION` (rested blue / normal purple). The colors were only applied at login and on settings changes.
- **Prevention:** `InstallExpBarColorGuard` overrides `SetStatusBarColor`/`SetVertexColor` on both instances. The same rule as above applies: any color, texture or visibility we set on a native frame needs a guard or a reassert. Status: fixed and live-confirmed (zone change, level up, rest area, reload). Off-state revert now repaints via native ExhaustionTick_Update, because the stored native snapshot was taken before the game painted its rest-state color.

---

## Frames, strata and layout

### Same-strata level race with the art frame
- **What happened:** Bar 1 vanished behind `MainMenuBarArtFrame` after a click on the art, and Key Ring stayed hidden behind it.
- **Root cause:** both shared the art's strata and relied on level. The art `:Raise()`s itself on click.
- **Prevention:** pin the art frame's strata/level and keep our elements at a higher level, reasserted on every apply. Set strata explicitly on each frame (cooldown children too), never through inheritance.

### Moving bars to HIGH covered the bags
- **What happened:** the HIGH-strata fix above made open bags draw behind the action bars, Bag Bar, Micro Menu, Key Ring and Page Indicator.
- **Root cause:** bags are MEDIUM. HIGH beats them unconditionally.
- **Prevention:** pick strata against *every* native window that can overlap, not just the frame being fixed. Now LOW with the art at LOW level 5, and `MainMenuBar:EnableMouse(false)`.

### Overlay tie-breaks undefined
- **What happened:** Bag Bar's edit overlay won clicks meant for Key Ring's.
- **Root cause:** same strata and level ties are undefined. The Key Ring overlay was also parented to the native frame, which put it in a different level tree.
- **Prevention:** parent every overlay to `UIParent` and give overlapping overlays distinct levels. Every disable path must hide its overlay itself.

### Hidden buttons in chain layouts
- **What happened:** a gap appeared in the Micro Menu after the Spellbook button.
- **Root cause:** `TalentMicroButton` is hidden below level 10 but was still chain-anchored.
- **Prevention:** filter on `IsShown()` live on every layout pass, and hook the native decision function (`UpdateMicroButtons`).

### Hiding `MainMenuBarArtFrame` wholesale
- **What happened:** hiding the art frame would also hide `ActionButton1-12`.
- **Root cause:** those buttons are its children.
- **Prevention:** hide only the `Texture` entries of `GetRegions()`.

### Frame without size never gets a rect
- **What happened:** the Page Indicator container's `GetLeft()` stayed `nil`, and the settle retry loop never ended.
- **Root cause:** a frame with `SetPoint` but no size never resolves its rect (env §4.6).
- **Prevention:** give containers a placeholder `SetWidth(1)`/`SetHeight(1)` at creation.

### Same-named `CreateFrame` on rebuild
- **What happened:** after switching pages, the stance/page dropdowns rendered with a fragmented skin and a blank label.
- **Root cause:** reusing a name creates a second frame, and native dropdown code finds the wrong one via `getglobal` (env §4.7).
- **Prevention:** suffix a per-rebuild counter onto every name on paths that can run twice.

### Overlay parented to UIParent measured wrong
- **What happened:** the Exp Bar text overlay sat off-center; `GetWidth()` read 921.6 vs the bar's 1024.
- **Root cause:** `GetWidth` is in local units, and those differ across ancestor chains even when the frames align visually.
- **Prevention:** parent tracking overlays into the tracked frame when their size is read.

### Absolute-pixel layout with nudge constants
- **What happened:** Page Indicator spacing came from measured gaps plus hand-tuned constants, and it broke on other setups. Key Ring resolved its native anchor live and ended up 1–2 px high after a regroup.
- **Root cause:** rect deltas and live anchors were read after something else had already moved.
- **Prevention:** rebuild from `GetPoint` data captured before reparenting, or from a login snapshot taken before anything moves.

### Cloning native border art
- **What happened:** two attempts to clone `MainMenuXPBarTexture0-3` for the Exp Bar's bottom 3 px rendered as a duplicate bar, then as distortion. A flat black cap before that had just hidden the real border art.
- **Root cause:** atlas tex-coords aren't reproducible from the calls available.
- **Prevention:** the gradient strip is final. Don't retry without a live tex-coord dump that explains the distortion.

### Border on the real `ShapeshiftButton`
- **What happened:** the Stance Bar icons turned grey.
- **Root cause:** `SetBackdrop` on the real button draws over its icon.
- **Prevention:** put the backdrop on a separate frame.

---

## Lua and API usage

### `X and X(...)` on multi-return APIs
- **What happened:** pet buttons showed a name but no icon, glow or autocast state.
- **Root cause:** `and`/`or` keep only the first return value.
- **Prevention:** capture multi-return calls inside an `if X then ... end` block.

### Skipping `subtext` in `GetPetActionInfo`
- **What happened:** every value after `name` shifted by one position.
- **Root cause:** position 2 is `subtext` (often `nil`, but present).
- **Prevention:** capture all 7 returns in order (env §4.11).

### Relying on `UPDATE_SHAPESHIFT_FORM` / `GetShapeshiftForm()`
- **What happened:** the styled Stance Bar never refreshed on form toggles.
- **Root cause:** those events never fire on toggles here, and `GetShapeshiftForm()` returns `nil`.
- **Prevention:** refresh on `PLAYER_AURAS_CHANGED`, and read `isActive` from `GetShapeshiftFormInfo`.

### `SetModel()` on the reparented autocast Model
- **What happened:** the autocast shine turned into a white plane.
- **Root cause:** `SetModel()` resets the native model.
- **Prevention:** resize with `SetModelScale` only.

### `PixelUtil.SetPoint` with a FontString
- **What happened:** login crashed with `PixelUtil.lua:66: attempt to call method 'GetEffectiveScale'`.
- **Root cause:** FontString/Texture regions have no `GetEffectiveScale`.
- **Prevention:** go through `ACAB:PixelSetPoint`, which falls back to plain `SetPoint`.

### Capturing a method after `Mixin()`
- **What happened:** `CreateListRow` recursed forever.
- **Root cause:** `Mixin` copies overrides onto the instance, so the "native" capture grabbed the override.
- **Prevention:** capture native methods before calling `Mixin`. The same applies to any capture-then-replace (Show neuters, color guards).

### Wrong texture path folder
- **What happened:** the rested tick rendered blank.
- **Root cause:** the path used the repo folder name instead of the installed AddOns folder name.
- **Prevention:** `Interface\AddOns\AlternativeClassicActionBars\...`, always.

### File load order
- **What happened:** "attempt to call nil value" on login.
- **Root cause:** `NativeElements.lua` made top-level `InstallShowGuard`/`InstallReanchorGuard` calls before `DefaultBars.lua` defined them.
- **Prevention:** keep the `.toc` order from `CLAUDE.md`. Top-level calls may only use functions defined in earlier files.

### Public scale setter inside a reset
- **What happened:** "Reset to Vanilla" landed in the wrong spot.
- **Root cause:** `Set<X>Scale(1)` compensates the position against the old scale.
- **Prevention:** resets write the scale directly, then resolve the native anchor (`ResetScaleAndResolveNative`).

---

## Input and settings UI

### `HookScript` to intercept native drags
- **What happened:** empty default-bar slots couldn't be dragged, and actions got picked up onto the cursor.
- **Root cause:** `HookScript` runs *after* the native `OnDragStart`, and empty areas had no frame to hook.
- **Prevention:** let our own overlay own the gesture with `SetScript`, stacked above the native buttons.

### Keyboard capture frame for Escape
- **What happened:** an `EnableKeyboard(true)` frame used to catch Escape blocked every other key.
- **Root cause:** keyboard capture on this client is all-or-nothing.
- **Prevention:** bind `ESCAPE` to a `bindings.xml` action temporarily, and never save it.

### Custom-bar keybinding via `SetBindingClick`
- **What happened:** the keys got recorded but did nothing.
- **Root cause:** `CLICK` bindings and `BONUSACTIONBUTTON` bindings never fire here.
- **Prevention:** declare actions in the shipped `bindings.xml` (env §4.4).

### Sliders fighting their own events
- **What happened:** sliders applied values while their range was being changed, and native drags broke mid-gesture.
- **Root cause:** `SetMinMaxValues` fires `OnValueChanged`, and calling `SetValue` from inside `OnValueChanged` breaks the drag.
- **Prevention:** set suppress flags around range changes, and never `SetValue` from the slider's own handler.

### Treating `GetXPExhaustion()` as rested bonus XP
- **What happened:** the rested fill and tick ran far past where the rested bonus actually ends (a 64% XP character's tick landed 67% into the next level instead of 34%).
- **Root cause:** the formula came from Blizzard's and BEB's `xp + GetXPExhaustion()`. On this server the pool drops 1.5 per bonus XP, so the raw value overstates the bonus by 1.5×.
- **Prevention:** before building on an API value's unit, measure it live: note the value before and after one real event (here, one rested kill) and compare against the chat numbers.

### Tick on the same draw layer as the overlay
- **What happened:** the rested tick rendered behind the colored rested fill.
- **Root cause:** both were `ARTWORK` textures on `MainMenuExpBar`, and order within a layer is undefined.
- **Prevention:** anything that must draw above another region on the same frame goes on a child frame with an explicit higher level.

### Exp Bar colors not reverting on disable
- **What happened:** turning Better Experience Bar off left the custom color in place.
- **Root cause:** the off branch was an early `return`.
- **Prevention:** "off" must actively restore the native baseline, not just skip applying.

### Backslashes lost through a shell heredoc
- **What happened:** the macro `?`-icon check never matched live. `Button.lua` held `"interface\icons\..."`: Lua reads `\i` as `i`, so the constant had no backslashes. `luac -p` accepted it, and the offline harness passed because its test string went through the same heredoc and lost its backslashes too.
- **Root cause:** code was written into a file through a bash heredoc / generated Lua script that collapsed `\\` to `\`.
- **Prevention:** write code and harness files that contain backslashes with the Edit/Write tools, never a shell heredoc. After any scripted edit, grep the result for texture paths with single backslashes.
