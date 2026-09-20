# Changelog

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
