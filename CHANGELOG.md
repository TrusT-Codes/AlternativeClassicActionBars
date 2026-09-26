# Changelog

## 1.2.1-beta

### Features

- **New Setup Wizard:** now runs inside the Settings window and shows your real settings pages - every change applies live to your bars while you set up, no more preview-then-apply. Covers General, Main Bar, Extra Bars, Stance/Pet Bar, Bag Bar, Key Ring, Experience Bar and Tooltip, with a "Drag Elements with Mouse" button to jump into Edit Layout mode and back. Reloads mid-setup pick up right where you left off.
- **New built-in profile "Default Modern"** (locked, like the renamed "Default Vanilla") - the baseline for the wizard's Modern layout.
- Better Experience Bar gets a new default earned-XP color and text size, and starts enabled on wizard-built profiles.
- Update checker now also listens on a hidden realm-wide channel and remembers the newest version it heard, so the update notice repeats every login until you update; `/acab version` shows your installed version.
- **GryphON or GryphOFF:** With the new Gryphon / Background Settings Dropdown on Mainbar's Settings-Page you can decide if you want the Gryphons, just the background, or everything disabled for a more modern & clean look.
- Blizzard's Main Bar art now moves and scales with Main Bar, in both Vanilla and Modern button style.
- While the art is shown, Bag Bar, Key Ring, Micro Menu, Latency Bar and Page Indicator stay in their vanilla spots on Main Bar; unlock any of them via its lock icon (settings page or Edit Layout mode) to move it freely.
- Settings that would break the art's alignment are locked while it's shown - hover to see why, click to jump to the responsible setting. Your own grid choices return once the art is off.
- Page Indicator now sits right of Main Bar, vertically centered, and follows it through any grid, size or move - until you drag it somewhere else.
- Bag Bar gets a Grid Layout option (5x1 or 1x5).
- Key Ring gets its own settings page (position, scale, hover-only, reset).
- Position X/Y are now measured from screen center to each element's visible center: 0/0 is dead center for every element, whatever its border style, grid or scale.
- Button spacing now scales with button size on every bar, so identically configured bars are always exactly the same size.
- Styled Pet Bar and Stance Bar get "Reset to Modern Layout Default"; all Vanilla/Modern resets now also restore default button size, spacing and scale.

### Bugfixes

- Fix update checker never alerting older clients: newer clients now answer older peers' version announcements.
- Fix Setup Wizard's "Keep Vanilla Layout" turning Page/Stance Swap back on after you disabled them.
- Fix styled Stance Bar's Reset to Vanilla Layout sizing it for 10 stances instead of your actual forms.
- Fix `/acab profile copy/import/export` overwriting the locked Default profile - now refused in chat.
- Fix a profile deleted on one character being recreated with defaults on another - now falls back to Default.
- Fix disabled Experience Bar reappearing on quest turn-in, level-up or other XP updates.
- Fix early XP/rest events on login touching settings before the profile loaded (errors on fresh installs).
- Fix hoverbind saving other buttons' temporary stance-swap keybinds, leaving native keys unbound after relog.
- Fix Extra Bars' action slots overlapping after shrinking a bar.
- Fix color picker Cancel not restoring the previous color; color options now grey out with Better Experience Bar off.
- Fix Setup Wizard slider readouts staying blank, and early finishes (Lock down / Keep Vanilla Layout) now reset global spacing/size to defaults.
- Fix spacing max: 20 in both button styles, no more shrink or overshoot when switching style.
- Fix Force Vanilla Layout not switching a styled Pet/Stance Bar to native - prompts a reload, settings page matches.
- Fix bar 5's Modern reset doing nothing with bar 4 disabled; Modern resets now restore bars 4/5 to 1x12.
- Fix Tooltip scale sticking to button and settings tooltips.
- Fix a click without moving dropping Page Indicator's follow-Main-Bar mode with snapping on.
- Fix the Main Bar art-dropdown highlight flickering on repeated clicks.
- Fix open bags hiding behind action bars, buttons, Bag Bar, Micro Menu, Key Ring and Page Indicator - bags now draw on top.

## 1.1.1-beta

- Add lightweight update checker (peer-announce over addon chat, nags once per session on a newer version)
- Fix bar-swap assignments not working for all Druid forms (Travel/Aquatic included)
- Fix stance-swapped default-bar buttons keeping their old keybind

## 1.1.0-beta

- Add Setup Wizard guiding initial addon setup, offering "Classic" and "Modern" base profiles
- Add Modern Layout option to the Setup Wizard: native/styled Pet-Stance mode, first-run profile fixes
- Extend Profiles page with a Setup Wizard button
- Make the Default-Layout warning banner clickable, jumping to the relevant settings
- Extend page/stance bar-swap to all default bars (Main Bar, Action Bar 1 & 2, Right Action Bar 1 & 2)
- Add README, release packaging script, and release workflow

## 1.0.0-beta

- Rename TrustyBars to Alternative Classic Action Bars (ACAB) and finish the 1.0 refactor
- Add customizable Cast Bar (position, scale, grid snap)
- Add customizable Pet Bar
- Add customizable Stance Bar styled mode with hoverbind support
- Add Edit Mode settings tab with layout grid and grid snapping
- Add "Only show on hover" toggle for every bar and element
- Add macro text display to action buttons
- Add movable/scalable Tooltip element to Edit Layout mode
- Add position fine-tuning: per-pixel X/Y sliders and accurate screen-edge clamping
- Add profiles, native action bar sync, and border-style unification
- Add profile export/import; fix copy-profile clobber bug
- Rework `/acab` into a full command set (edit, bind, help, menu, settings, profile)
- Stack Pet/Stance/Cast Bar dynamically in Default Layout mode
- Warn before enabling Default Blizzard Layout; fix its reset cascade
- Settings UI polish: tabs, scrollbars, list panel, and fade strips
- Convert plain-text setting descriptions to hover tooltips
- Micro Menu grid layout, spacing fix, and re-anchor guard
- Fix default-bar alignment on fresh install; add Pet Bar reflow
- Fix Pet/Stance Bar Spacing/ButtonSize sliders and per-bar global-override lock
- Fix Pet Bar Condense-empty-button-space not working in custom mode
- Fix Stance Bar backdrop leak, border style, and native border overlap
- Fix Latency Bar reset position, edit-mode hitbox, and native-anchor timing
- Fix Main Bar always showing empty-slot borders
- Fix Edit Layout snap priority/Shift-invert; add Alt-invert and ESC exit
- Fix edit-mode overlay/snapping accuracy; add global border-style, spacing and button-size controls
- Fix hoverbind mouse-button binds and Escape-clears-keybind
- Fix LatencyBar/BagBar/Keyring resetting or reappearing when toggled off
- Strip comment bloat, enforce WHAT-syntax going forward
