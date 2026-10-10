# Full Mana Forever

**The right mana potion at the right moment — for World of Warcraft: Forever (WoW Forever, Classic+).**

A mana potion, rune, mana gem or your own mana spell (Evocation, Innervate, Mana Tide, ...) lights up the moment it is ready **and** fits into your missing mana: nothing is wasted. Plus a compact mana bar with the **five-second rule (5SR)** and your **live mana regen per second, also in combat**. Made for healers first, useful for every mana user.

*Features asked for in the comments get built. Tell us what you need: comment here or open an issue on [GitHub](https://github.com/KesaObscura/FullManaForever/issues).*

## What it does

- **Icons that light up at the right time.** One icon per cooldown group: mana potions, Demonic/Dark Runes, mage mana gems, other mana consumables, and use effects of equipped gear.
- **Right potion for the deficit.** With several potions in your bags, the icon shows the **strongest potion that will not overflow**: a weak one when you are slightly down, a strong one when you are low.
- **One simple setting: When to light up.** *No waste* waits until the whole potion fits. *More per fight* uses the average restore, so you drink earlier and fit more potions into a long fight. *Strongest only* keeps it simple.
- **Runes are safe.** A rune is only shown when you will keep a configurable share of your health after its damage (30 % by default).
- **Your own mana spells too.** Evocation, Innervate, Mana Tide Totem, Inner Focus, Life Tap and the racials Eureka! (gnome) and Ley Line reading (Skyborne) get their own icon: it lights up when the spell is ready and your mana is at or below a share you choose (50 % by default). Life Tap lights up like a potion when its mana fits, with the same health check as runes. Forever hides spell cooldowns from addons in combat, so the addon counts them from your cast — never too early.
- **Made for wanding.** Each wand shot blocks potions and spells for a moment. The icon stays lit and shows that short wait as a sweep, like the action bar: the potion fits, stop shooting and drink.
- **Mana bar with markers.** A compact mana bar with the current value and a marker for every potion step. Icons in a row or in a column, bar under, above, left or right; bar color, thickness and length (auto: room for the groups you switched on), icon size and spacing are adjustable. Nothing is shown while you are dead or a ghost.
- **Five-second rule and mana regen.** After a spell that costs mana, a gold strip and the seconds next to the mana bar count down the 5 seconds of reduced regen (wands, potions and food do not start it). Next to the mana bar (under the numbers when the icons are in a column) you see the regen running right now, per second — also in combat, and including talents like Spirit Tap or Innervate.
- **Regen your way.** The regen turns green when it is above your normal rate (drinking, Spirit Tap, ... out of combat, and in combat after your own Evocation or Ley Line reading — Forever hides the value from addons in combat). The mana numbers, the five-second seconds and the regen also show with the mana bar switched off, and *Move texts freely* lets you drag each of them anywhere.
- **Mana text** like the game's status text: numeric value, percentage or both, with its own switch and text size.
- **Settings that explain themselves.** Hover any option for a short explanation. *Reset position* and *Reset size* undo your experiments in one click.
- **Item list.** See every supported item with icon, restore value and whether you carry it. Turn single items off (for example to save expensive potions) or add your own item to any category.
- **Profiles per character.** All characters share one set of settings, or a character gets its own (a copy of the shared ones to start with). Copy the settings of another character in one click, reset a profile or delete the settings of characters you no longer play; one undo if you clicked the wrong one. Language and your own items stay the same for all.
- **Sound when your potion is ready again** (optional): a short chime when the mana potion cooldown is over, also in combat.
- **Show only where you need it.** Solo, in a party, in a raid — any combination, and optionally only in combat.
- **Hold potions.** `/fmf hold` (best in a macro) holds mana potions until the end of the next fight, for when you want the potion cooldown for something else. The potion icon turns grey with "HOLD"; after the fight it releases by itself.
- Only suggests what you can use: skips items above your level, mage-only items for other classes and battleground-only items outside battlegrounds.
- 9 languages: English, Deutsch, Español (EU and AL), Français, Русский, 한국어, Português, 简体中文, 繁體中文.

## Looking for a mana tick or mp5 tracker?

Forever's mana regen is continuous: there are no 2-second mana ticks, and addons cannot read your mana or regen in combat, so classic mana tick and mp5 trackers do not work here. Full Mana Forever shows what really counts in Forever: the **five-second rule** countdown after each spell and the **regen running right now, per second**, in and out of combat.

## Built for Forever's addon rules

Forever hides your current mana, your buffs and your spell cooldowns from addons in combat. Full Mana Forever does not try to read them: it hands the mana check to the game itself (a step curve on `UnitPowerPercent`), and the game shows or hides the icon. It reads only what Forever allows (item cooldowns, maximum mana, your own casts). No automation: the addon never uses an item or casts for you, you press the button.

## Supported items (checked against the Forever database)

- **Mana potions** (shared cooldown): Major, Major Rejuvenation, Superior, Greater, Mana, Lesser, Minor, Minor Rejuvenation, Dreamless Sleep (off by default — it puts you to sleep for 12 s).
- **Runes:** Demonic Rune, Dark Rune.
- **Mana gems (mage):** Ruby, Citrine, Jade, Agate.
- **Other:** Night Dragon's Breath, Major/Superior Mana Draught (battlegrounds only).
- **Gear:** Warmth of Forgiveness, Major/Minor Recombobulator, Robe of the Archmage (mage).

## Commands

| Command | Does |
|---|---|
| `/fmf` | open the settings |
| `/fmf items` | open the item list |
| `/fmf profile` | profile in use and characters with own settings; `/fmf profile shared` / `own` switches, `copy <name>` takes over another character's settings, `undo` takes back the last copy |
| `/fmf hold` | hold mana potions until the end of the next fight (grey "HOLD" icon); again releases them. Tip: put it in a macro |
| `/fmf unlock` / `/fmf lock` | move the icons |
| `/fmf test` | same as `/fmf unlock`: show everything that is switched on, to place the frame |
| `/fmf reset` | move the icons back to the default position |
| `/fmf reset size` | icon size, spacing, bar thickness, bar length and text sizes back to the defaults |
| `/fmf probe` | print API status for bug reports |
| `/fmf log on` / `/fmf log off` | record casts and regen for a bug report |
| `/fmf scan` | write your spells, talents and use items into the log, for a bug report |

The settings are also in *Options → AddOns → Full Mana Forever* and in the addon menu at the minimap.

## FAQ

- **Does it work in combat?** Yes, it was built and tested for combat in Forever.
- **Does it drink for me?** No. The icon tells you when; you press your potion button.
- **Does it work in WoW Classic Era, Hardcore or retail?** No. It is made for World of Warcraft: Forever (client 1.60.1) and its addon rules.
- **Why does the icon not light up at 90 % mana?** *No waste*: it waits until the whole potion fits into your missing mana. Want to drink earlier? Switch *When to light up* to *More per fight*.
- **Different settings for my healer and my mage?** Yes: each character can have its own profile, or copy another character's settings.
- **How do I save my expensive potions?** Switch single items off in `/fmf items`, or hold potions for one fight with `/fmf hold`.

## Tested so far

Works in combat. Tested in Forever at low level: priest 16–20 (also with Spirit Tap for the regen display; a mana potion comes back after its 2-minute cooldown in the same fight; wanding; own spells with the gnome's Eureka! and Inner Focus, in and out of combat), Ley Line reading on a Skyborne mage, the regen colours while drinking, with Spirit Tap and after Ley Line reading, per-character profiles across several characters and `/fmf hold` in and out of combat. Level-60 items (runes, raid trinkets) and the other own spells (Evocation, Innervate, Mana Tide, Life Tap) could not be tested in the beta yet. Please report anything odd — see *Bug reports* below.

## Planned

Pre-pull checklist (consumables, buffs), who in your group has Innervate / Mana Tide ready, group sync of mana cooldowns (Innervate, Mana Tide) and a helper for the druid or shaman giving them out.

## Bug reports

Please include the output of `/fmf probe`, your class and level, and what you expected. Lua errors are easiest to read with BugGrabber + BugSack.

For the five-second rule or the regen display: `/fmf log on`, play until it happens, `/fmf log off`, `/reload`, and attach `WTF\Account\ACCOUNTNAME\SavedVariables\FullManaForever.lua` (class, level, casts and regen values; in a group also your group members' names and casts — remove them before sharing if you like).

Source code and issues: [GitHub](https://github.com/KesaObscura/FullManaForever).

Vollständig auf Deutsch · Totalmente en español · Entièrement en français · Полностью на русском · 한국어 완전 지원 · Totalmente em português · 完整简体中文 · 完整繁體中文 — the addon follows your game language.
