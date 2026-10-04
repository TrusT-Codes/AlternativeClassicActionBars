# Release Checklist

Run once per release candidate, in-game, on the real client. Copy the unchecked list into the release PR and tick items there; this file stays the template. Any failure gets a `known-problems.md` entry or a fix before tagging.

Before starting: turn on Lua error display (Interface Options), and back up `WTF/Account/<name>/SavedVariables/AlternativeClassicActionBars.lua` plus each character's copy.

---

## 1. Static checks

- [ ] `luac -p` passes on every `.lua` file listed in the `.toc`
- [ ] No `/acab diagN` commands, `DIAG` lines or temporary traces left (`grep -n "DIAG\|diag[0-9]" *.lua`)
- [ ] Every new file is in `AlternativeClassicActionBars.toc` in load order
- [ ] `CHANGELOG.md` "Unreleased" lists every user-visible change since the last tag
- [ ] `scripts/Build-Release.ps1 -Version <x.y.z>` builds; the zip unpacks to one `AlternativeClassicActionBars/` folder that loads in-game

## 2. Install and upgrade paths

Each path: log in, confirm "Fully initialized!" with no error box and no "Reset invalid saved settings" line.

- [ ] **Fresh install** (SavedVariables deleted): first-login dialog appears
  - [ ] Wizard → Vanilla (locked): bars on the native Blizzard spots
  - [ ] Wizard → Vanilla (unlocked): bars on the native spots, not ~76 px left
  - [ ] Wizard → Modern: layout baseline applies, one automatic reload, wizard resumes on the next page
  - [ ] Skip the wizard: Default Vanilla active, nothing moved
- [ ] **Upgrade from the last public release**: old SavedVariables + new build, all bars/elements where they were, profile list intact
- [ ] **Upgrade from 1.2.0 / older beta** (if a backup exists): same as above
- [ ] `/reload` vs. full logout → login: enabled Action Bars 2–5 stay enabled after a real logout
- [ ] Second character on the same account: per-character profile selection kept, account-wide profiles shared
- [ ] **Missing ClassicAPI**: one red chat line, no bars touched, `/acab` answers "Disabled"

## 3. Classes and bar states

- [ ] **Druid**: Bear/Cat page swap on Main Bar; Travel/Aquatic keep page 1; Stance Bar updates on each form; learning a new form shows it without a reload
- [ ] **Warrior**: stance swap pages Main Bar; stance assignments per bar apply
- [ ] **Rogue**: Stealth pages Main Bar; Stance Bar appears after learning Stealth
- [ ] **Hunter / Warlock**: Pet Bar shows on summon, hides on dismiss; drag pet spells on/off; right-click toggles autocast; autocast shine above the button
- [ ] **Class without stances** (Mage/Priest): no Stance Bar, no errors
- [ ] Styled and native ("Use Vanilla") Pet Bar and Stance Bar both work, and switching between them reloads cleanly
- [ ] Main Bar paging via ActionBarUp/Down and Shift+1–6

## 4. Layout and display

- [ ] UI scale 0.64 and 1.0 (or off): Vanilla layout matches the native spots at both
- [ ] Two resolutions / aspect ratios (e.g. 1920×1080 and 2560×1440 or 4:3)
- [ ] Edit Layout mode: drag every element, snap-to-grid, snap-to-adjacent, Escape exits, all overlays gone after exit
- [ ] Main Bar art modes (full / no gryphons / disabled): grouped Bag Bar, Key Ring, Micro Menu, Latency Bar, Page Indicator follow Main Bar; unlocking each one frees it
- [ ] Every element's "Reset to Vanilla" / "Reset to Modern" lands on the right spot
- [ ] Force Vanilla Layout toggle resets everything and restacks Stance/Pet/Cast Bar
- [ ] Open all bags: bags draw above every bar and element
- [ ] Hover-only fade on bars and elements
- [ ] Experience Bar: Better Experience Bar colors survive a zone change, level-up and rest-area change; turning it off restores native purple/blue; disabled Exp Bar stays hidden after quest turn-in / XP gain
- [ ] Tooltip anchor and scale; Cast Bar position while casting

## 5. Input and profiles

- [ ] Hoverbind: bind default-bar and Extra Bar buttons, keys fire after `/reload` and relog
- [ ] Profiles: create, copy, delete, switch (reloads), export → import round-trip gives an identical layout
- [ ] Import a corrupted or truncated string: clear error message, no Lua error, no profile created
- [ ] Built-in profiles (Default Vanilla / Default Modern) refuse delete and import
- [ ] Every `/acab` command from `/acab help`

## 6. Combat and load

- [ ] Real combat: buttons fire, cooldown spirals, range tint, usable/unusable state, no taint or blocked-action messages
- [ ] Latency Bar / Key Ring hold position after combat, looting and zoning
- [ ] Raid or busy city for 10+ minutes: no FPS drop vs. the addon disabled; `/run print(gcinfo())` before/after does not keep climbing
- [ ] Open and close the Settings window ~50 times across pages: `gcinfo()` does not keep climbing

## 7. Other addons and clients

- [ ] With the user's usual addon set (unit frames, bag addons, pfUI if relevant): no fights over `MainMenuBar`, no double bars
- [ ] Non-English client, if available: rested-XP calibration after one rested kill (see known-problems "Rested overlay uses bonus XP")
- [ ] Update check: an older build on a second account in the same guild/party gets the update notice

## 8. Tag and ship

- [ ] Commit `.toc` `## Version:` bumped to the new version
- [ ] `CHANGELOG.md`: rename "Unreleased" to the version
- [ ] Merge into `release/<x.y>.x`, then into `main`
- [ ] Push tag `v<x.y.z>` (no `-suffix` = full release, not marked prerelease)
- [ ] Download the zip from the GitHub Release, install it clean, log in once
