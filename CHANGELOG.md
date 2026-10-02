# Changelog

**0.6.8 beta**

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

**0.6.7 beta**

- Fixed: after locking, the icons no longer jump away from where you placed them (row and column layout); the frame is now pinned by its top-left corner
- Removed: FMF_* macros. A macro cannot see your mana, so it could not match the icon; put your potions on the action bar directly
- Old FMF_* macros are deleted once (out of combat) for everyone who had the option switched on
- Settings: the "Drinking" explanations no longer mention macros
- New option "Show": solo / in a party / in a raid, any combination (works together with "Only in combat")

**0.6.6 beta**

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

**0.6.5 beta**

- New option: mana bar under or above the icons (shown only while the mana bar is on)
- Empty-group placeholders in test/unlock mode now show the group's own item icon (greyed) instead of a question mark

**0.6.4 beta**

- Item list: visible scrollbar with a draggable thumb (mouse wheel works on the list and on the bar)
- CurseForge project ID added to the TOC

**0.6.3 beta — first public release**

- Icons for mana potions, runes, mage gems, other mana consumables and equipped gear, shown only when ready and your mana deficit is large enough
- Potion choice by deficit (strongest potion that will not overflow) or always the strongest
- Threshold modes: no waste (maximum) / most per fight (average)
- Rune health safety margin
- Mana bar with markers and current value
- Optional auto macros; the potion macro chains potions strongest to weakest
- Item list with per-item on/off and custom items per category
- /fmf hold, 10 languages
