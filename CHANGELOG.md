# Changelog

**Full Mana Forever 0.7.0**

- New: five-second rule on the mana bar. After a spell that costs mana, a thin gold strip and the seconds at the end of the bar count down the 5 seconds of reduced regen. Wands, potions and food do not start it.
- New: the mana regen running right now, per second, under the mana numbers ("14.8/s"). During the five-second rule it turns gold and shows what still runs while you cast: 0 without talents, more with talents, Innervate or gear. It also works in combat.
- New: mana text like the game's "Status Text": numeric value, percentage, both or none.
- New: `/fmf log on` / `off` records what the game reports (casts, mana costs, regen) for bug reports.
- The five-second rule and the regen can be switched off under "Mana bar with markers", and both have their own text size (60–200 %). "Reset size" resets these text sizes too.
- Mana bar markers stay inside the bar: the one where the icon lights up is thick and bright, the others thin (before, it stuck out at the sides).

**Full Mana Forever 0.6.10**

- Fixed: items above your level (for example Mana Potion before level 22) are no longer suggested; the strongest potion you can actually drink is shown instead
- Item list: items above your level say which level they need

**Full Mana Forever 0.6.9**

- New: "Reset size" button (under the size settings) and `/fmf reset size`: icon size, icon spacing, bar thickness and bar length go back to the defaults (position, colors and layout stay)
- Settings window reworked:
  - all -/+ buttons in one column, values in one column, all dropdowns the same width
  - -/+ are greyed out when they would not change anything
  - bar length: + from "auto" starts at the auto length instead of 20; going below the icon size returns to "auto"
  - new section "Visibility" on the right: "Show only in combat" and solo / party / raid
  - consumables with nothing in the bags (or switched off) take one line instead of two
  - tooltips on the settings; clicking a checkbox label toggles it
  - the "Drinking" explanation is easier to read
  - the settings window and the item list are no longer see-through
- Item list: keeps its place and scroll position when you change the language; wider, so "up to N" and "not in bags" no longer overlap in long languages, and nothing is cut off at the right edge at any UI scale
- Trinkets & gear: says "nothing equipped" instead of "none in bags"

**Full Mana Forever 0.6.8**

- Faster: about 27 times less memory churn and half the item API calls per update
- Safer: if the game's mana check stops working, icons stay hidden instead of lighting up at full mana
- One broken item or group no longer hides all the other icons
- Own items: the amount must be a whole number from 1 to 99999; an own entry for a known item replaces it in that category instead of showing twice, keeps the rune health check and the sleep warning, and without a category it stays in its own one
- Equal restore: Dreamless Sleep is never suggested over a normal potion
- Item list: updates after /fmf item and /fmf item clear, the scrollbar can be dragged, no hidden frames pile up anymore
- Mana bar: shows empty instead of full if mana cannot be read; the mana numbers come back after a loading screen
- Old FMF_* macros: removal is retried when macro data loads later than login
- Settings: only one dropdown open at a time, the window comes to the front when clicked, long status lines no longer overlap, picking the current layout or language no longer rebuilds the window
- Texts: unused strings removed, the "Add own item" hint and /fmf help updated (category argument)
- Automated tests (tests/run.lua), not part of the release zip

**Full Mana Forever 0.6.7**

- Fixed: after locking, the icons no longer jump away from where you placed them (row and column layout); the frame is now pinned by its top-left corner
- Removed: FMF_* macros. A macro cannot see your mana, so it could not match the icon; put your potions on the action bar directly
- Old FMF_* macros are deleted once (out of combat) for everyone who had the option switched on
- Settings: the "Drinking" explanations no longer mention macros
- New option "Show": solo / in a party / in a raid, any combination (works together with "Only in combat")

**Full Mana Forever 0.6.6**

- New layout: icons in a column with a vertical mana bar on the left or right (the bar empties from the top down)
- New look: icons with a thin dark frame, soft shadow and light from the top; outlined count
- Mana bar redrawn: gradient fill, glass highlight, shadow, outlined numbers and markers
- Mana bar options: color (4 colors), thickness, length (auto or fixed); auto length no longer changes with the number of icons
- Icon spacing option
- Mana bar markers for every potion step: long marker = the icon lights up, short ones = a stronger potion becomes the best fit
- "Potion choice" and "Threshold" merged into one setting "Drinking": No waste / More per fight / Strongest only, with a short explanation
- FMF_Potion macro in "No waste" and "More per fight" drinks the weakest potion first (macros cannot see mana; the weakest never overflows); "Strongest only" keeps the strongest first
- Fixed: the status line named the strongest potion with the threshold of the weakest
- Settings window in two columns: display and look on the left, consumables on the right

**Full Mana Forever 0.6.5**

- New option: mana bar under or above the icons (shown only while the mana bar is on)
- Empty-group placeholders in test/unlock mode now show the group's own item icon (greyed) instead of a question mark

**Full Mana Forever 0.6.4**

- Item list: visible scrollbar with a draggable thumb (mouse wheel works on the list and on the bar)
- CurseForge project ID added to the TOC

**Full Mana Forever 0.6.3**

- Icons for mana potions, runes, mage gems, other mana consumables and equipped gear, shown only when ready and your mana deficit is large enough
- Potion choice by deficit (strongest potion that will not overflow) or always the strongest
- Threshold modes: no waste (maximum) / most per fight (average)
- Rune health safety margin
- Mana bar with markers and current value
- Optional auto macros; the potion macro chains potions strongest to weakest
- Item list with per-item on/off and custom items per category
- /fmf hold, 10 languages
