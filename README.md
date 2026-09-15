<div align="center">

# <span style="color:red">A</span>lternative<span style="color:red">C</span>lassic<span style="color:red">A</span>ction<span style="color:red">B</span>ars

### (ACAB)

**An action bar addon inspired by Bartender, built to keep the original Vanilla aesthetic while adding real quality-of-life features.**

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)
![Client](https://img.shields.io/badge/client-1.12.1-orange.svg)
![OctoWoW](https://img.shields.io/badge/client-OctoWoW-green.svg)

Brougt to you by **Trusty**

</div>

## What is this?

**AlternativeClassicActionBars (ACAB)** improves on the classic Vanilla action bars — it doesn't replace or restyle them. The native look and feel stays exactly as it is if that's what you want; ACAB layers Bartender2-style customization on top, so you get free layout control without giving up the Classic UI's aesthetic.

Reposition, resize, and reorganize every native UI element — action bars, pet bar, stance bar, bag bar, micro menu, key ring, latency/cast bars, XP bar, tooltip — and add extra custom action bars beyond the default five, all with drag-to-place editing and per-profile saved layouts.

It's tested and developed specifically for the **OctoWoW** client.

## Dependencies

Requires a [**ClassicAPI**](https://octowow.st/git/brues/ClassicAPI)-extended client.

## Disclaimer

Claude Code was used heavily throughout development of this addon. Every change was thoroughly checked for performance and intensively tested in-client by myself before being shipped.

## Showcase

<!--
  Drop screenshots or GIFs here to show off Edit Layout mode, custom bars,
  the Experience Bar overlay, profiles, etc. Example:
  ![Edit Layout mode](docs/media/edit-mode.gif)
-->
*Screenshots and GIFs coming soon.*

## ⭐ Spotlight: Hoverbind

Hoverbind is the fastest way to rebind your action bars, and one of the biggest quality-of-life upgrades ACAB adds. Instead of digging through the Blizzard keybinding menu:

1. Toggle Hoverbind mode with `/acab bind` or use the dropdown from the Minimap Menu
2. Hover your mouse over any button
3. Press the key (or key combo) you want — it's bound instantly

That's it. No menu, no scrolling through a giant list looking for the right slot — just hover and press.

## Features

- **Edit Layout mode** — drag any bar or element with snap-to-grid and snap-to-adjacent-element alignment
- **Custom action bars** — add extra bars beyond the default five, each its own grid of size/position/columns/rows
- **Native element styling / positioning** — reposition and rescale the Bag Bar, Micro Menu, Key Ring, Latency Bar, Cast Bar, Page Indicator, and Tooltip without losing native behavior
- **Vanilla OR Improved Pet Bar & Stance Bar** — Use the native UI Pet or Stance Bar OR use the improved ActionBar Styled Bars. Both offering you the option to scale, move and align them however you desire
- **Better Experience Bar** — Optionally enable functionality inspired by the **BetterExperienceBar** Addon. Shows total / percentage of RestedXP. Change colors of the Exp-Bar and more. Try it out!
- **Profiles** — create, copy, export, and import full layout profiles
- **Minimap launcher** — quick access via a draggable minimap button and right-click menu

## Installation

1. Download the latest release zip from the [Releases](../../releases) page
2. Extract it into your client's `Interface/AddOns/` folder. NEEDS to be in `AlternativeClassicActionBars` folder to work. Make sure no Version / `master` is included in the Folder name.
3. Enable **AlternativeClassicActionBars (ACAB)** at the character select AddOns screen

## Commands

All commands start with `/acab`.

| Command | Description |
|---|---|
| `/acab` | Toggle the Settings window |
| `/acab menu` | Open the minimap right-click menu |
| `/acab edit` | Toggle Edit Layout mode |
| `/acab bind` | Toggle Hoverbind keybind mode |
| `/acab settings <page>` | Jump straight to a settings page |
| `/acab profile` | Show current profile and profile commands |
| `/acab profile list` | List all profiles |
| `/acab profile select <name>` | Switch to another profile |
| `/acab profile add <name>` | Create a new profile |
| `/acab profile delete <name>` | Delete a profile |
| `/acab profile copy [name]` | Copy settings from another profile into the current one |
| `/acab profile export` | Show the current profile's export string |
| `/acab profile import` | Paste an export string into the current profile |
| `/acab recapture` | Force a fresh capture of default bar native anchors |
| `/acab help` | List all commands in-game |

## Credits

- **ButtonForge Classic** (MIT-licensed) — the native action-slot button pattern this addon's buttons are built on
- **Better Experience Bar (BEB)** — the rested-XP tick overlay and its art, ported into this addon's Experience Bar

## License

[GNU GPLv3](LICENSE)
