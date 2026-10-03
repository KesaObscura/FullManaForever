# Full Mana Forever

An addon for **World of Warcraft: Forever** (client 1.60.1, interface 16001) for healers
and every other mana user.

It shows a mana potion, rune or mana item **the moment you can use it without waste**:
the item is off cooldown *and* your missing mana is at least what it restores. Drink on
cooldown, stay near full mana, and never panic-chug at 5 %.

## How it works with Forever's addon rules

In Forever your current mana is a *secret value*: addons cannot read or compare it.
Full Mana Forever never tries to. It gives the game a step curve
(`C_CurveUtil` + `UnitPowerPercent`), the game evaluates it and returns a secret alpha,
and that alpha is applied straight to the icon. Nested frames multiply their alpha, which
gives "ready **and** deficit big enough (**and** enough health for runes)".
Item cooldowns, item counts and maximum mana are readable and handled normally.

The addon never uses an item for you. Put your potions on the action bar and press them
when the icon lights up.

## Features

- One icon per cooldown group: mana potions, Demonic/Dark Rune, mage mana gems, other
  mana consumables, and use effects of equipped gear.
- **Right potion for the deficit**: with several potions in your bags the icon shows the
  strongest one that will not overflow.
- **Drinking** setting: *No waste* (default) waits until the whole potion fits;
  *More per fight* uses the average restore (earlier, sometimes a small overflow);
  *Strongest only*.
- **Runes are safe**: shown only if you keep a set share of health after the rune
  (30 % by default).
- **Mana bar with markers**: a long marker where an icon lights up, short ones where a
  stronger potion becomes the best fit. Icons in a row or a column, bar on any side;
  color, thickness, length, icon size and spacing are adjustable.
- **Show**: solo / in a party / in a raid, optionally only in combat.
- **Item list** (`/fmf items`): every supported item, on/off per item, add your own.
- 10 languages: English, Deutsch, Español (EU/AL), Français, Русский, 한국어, Português,
  繁體中文, 简体中文.

Supported items and their restore values are in [`Data.lua`](Data.lua); they were checked
against the Wowhead Forever database (build 1.60.1). Dreamless Sleep Potion is off by
default because it puts you to sleep for 12 seconds.

## Install

Recommended: install it from [CurseForge](https://www.curseforge.com/wow/addons/full-mana-forever) (the CurseForge app keeps it up to date).

Manual install: download a release zip and unpack it into
`<your WoW Forever client folder>/Interface/AddOns/`. The result must be
`Interface/AddOns/FullManaForever/FullManaForever.toc`. If you use GitHub's
"Download ZIP", rename the folder from `FullManaForever-main` to `FullManaForever`,
otherwise the game does not load it.

## Commands

| Command | Does |
|---|---|
| `/fmf` | open the settings (also in Options → AddOns and the addon menu at the minimap) |
| `/fmf items` | open the item list |
| `/fmf hold` | hold / release potion suggestions |
| `/fmf unlock` / `/fmf lock` | move the icons |
| `/fmf test` | show icons whenever an item is ready, ignoring mana |
| `/fmf item <id> <amount> [potion\|rune\|gem\|herb\|gear]` | add your own item |
| `/fmf item clear` | remove all own items |
| `/fmf probe` | print API status for bug reports |
| `/fmf debug` | debug messages on/off |
| `/fmf scale` | switch the curve scale 0..1 / 0..100 (only if icons never react) |
| `/fmf reset` | reset the position |
| `/fmf reset size` | reset icon size, icon spacing, bar thickness and bar length |

## Bug reports

Please open an [issue](https://github.com/KesaObscura/FullManaForever/issues) with the output of `/fmf probe`, your class and level, what you
did and what you expected. Lua errors are easiest to read with BugGrabber + BugSack.

## Development

Plain Lua 5.1, no libraries, no Blizzard templates. Files load in TOC order:
`Locale.lua` → `Data.lua` → `Core.lua` → `Options.lua` → `Library.lua`.

Tests run outside the game against a small mock of the WoW API:

```
lua5.1 tests/run.lua
```

They cover the mana/cooldown logic, custom items, the UI windows, the locale tables
(every language has every key with the same placeholders) and a per-update performance
budget. The `tests` folder is not part of the release zip (see `.pkgmeta`).

**Translations**: all texts are in `Locale.lua`. Every language must have exactly the
keys of `enUS` with the same `%s`/`%d` placeholders; `tests/run.lua` checks that.

## License

[MIT](LICENSE)
