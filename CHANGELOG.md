# Changelog

**Full Mana Forever 0.8.10**

- Own icon in the game: the addon list and the addon menu at the minimap now show the Full Mana Forever flask instead of a plain mana potion

**Full Mana Forever 0.8.9**

- Regen colour after death: the lowered regen under Resurrection Sickness (or anything else that takes at least half of your Spirit or Intellect) is no longer taken as your normal regen, so your normal regen no longer turns green with the up arrow once the debuff ends. Gear with a few points less Spirit still counts as normal
- While such a debuff lasts, the regen is shown red with a small down arrow
- Major and Superior Mana Draught (battlegrounds) share the potion cooldown, as the game shows: in battlegrounds they now use the potion icon (the strongest that fits) instead of a second icon that always went on cooldown together with it
- More potions in the potion slot, all with the shared potion cooldown read from the game: Forever's Restored Mana Potion (20 % of your max mana, so it fits at every level), Tessa's Tonic, Diet McWeaksauce, Mug of Shimmer Stout, Full Moonshine and Forever's second item IDs of the Minor and Lesser Mana Potion (usable from level 1; one row in the list with the original, counted and switched together). Wildvine Potion is listed but off by default (it may restore nothing)
- Forever's Power Recycler (20 % of your max health into 20 % of your max mana) in "Other consumables", with the health check of the runes; also Tea with Sugar and, for mages, the Scroll of Minor Evocation
- Gear: Earthen Sigil (trinket) and, for druids, the Veildust Medicine Bag (off-hand)
- Celestial Orb, Arcane Orb and Ley Orb are mage items ("Classes: Mage"): no longer listed for other classes

**Full Mana Forever 0.8.8**

- New setting "Show icons before ready" (top of Visibility, 5 s by default, off to 60 in steps of 5): potions, runes, gems, other consumables, gear and your own spells already show in the last seconds of their cooldown, grey and without glow, with the game's own countdown on them like on the action bar ("1:55", "3m", "5"). When the cooldown is over they light up as before; at 0 they only show when ready. The mana rules stay the same, and spell cooldowns are counted from your cast in combat as before

**Full Mana Forever 0.8.7**

- The item list is now "Items and spells" (also the button in the settings): your class's own mana spells (Evocation, Innervate, Mana Tide Totem, Inner Focus, Life Tap and your race's Eureka! or Ley Line reading) are listed there with on/off, and a spell you do not have yet says why: the level it is learned at (read from the game), a talent, or the trainer
- Each spell has its own mana threshold, set with - / + in the list, with sensible defaults: Eureka! 90 %, Inner Focus 75 %, Ley Line reading 70 %, Mana Tide Totem 60 %, Innervate 40 %, Evocation 35 %. Life Tap still lights up when its mana fits. The common setting "Light up at mana <=" is gone; if you had changed it, every spell keeps your value
- Several spells ready at once each get their own icon (up to 3), highest threshold first, so lit icons never leave a gap
- The automatic bar length has room for every spell icon. A bar you set shorter than the icon column keeps your length; the mana numbers and the regen then sit beside the bar, on the side away from the icons, instead of over the last icons
- Esc after a language change works as before: first the item list, then the settings, the third press opens the game menu (the rebuilt windows did not take over their names, so Esc looked at the old ones)
- Settings: "Move texts freely" always sits under "Unlock frame", indented, in every language (it jumped when the language changed)
- In the list, notes after a name ("own", "sleep 12 s!", "BG only") are never cut off; a long name ends in "..." instead (the full name is in its tooltip). The window is a little wider
- Each ready spell has its own mark on the mana bar; a spell on cooldown has none (before, the first spell's mark stayed while it was on cooldown)
- New items, checked against the game's own texts: Combat Mana Potion, Greater Dreamless Sleep Potion (off by default, like Dreamless Sleep), Energy Cloak (its use effect is new in Forever), Celestial Orb, Arcane Orb and Ley Orb

**Full Mana Forever 0.8.6**

Stability and speed, found in a full review of the code; what the addon does stays the same.

- Profiles know Forever's surnames: two characters with the same first name no longer share one profile; your own settings move over by themselves. `/fmf profile copy` takes the full name (`/fmf profile copy Anna Stone`), or only the first name when it is unique
- Inner Focus: if your spell book changed while its buff was up (new rank, talent), the icon no longer stays away until you leave combat
- Learning your first mana spell (or losing the last one) updates the auto bar length at once, not only after the icons change
- Undo in the profiles window takes back only that one change (a deleted profile comes back), not settings you changed afterwards
- Switching profiles with the settings closed no longer builds the settings window again each time (less memory) and no longer moves an open item list
- After a language change the profiles window and the "HOLD" word on the potion use the new language
- A damaged saved position (for example an edited settings file) no longer stops the addon at login; the frame goes back to its default place
- A mana band whose lower and upper edge are the same is never shown (before, the game got two curve points at one value)
- Less work per update: spell cooldowns and the battleground check are read once per update, a missing Life Tap text is asked for once a second

**Full Mana Forever 0.8.5**

- Regen above your normal rate also shows a small green up arrow after the number, not only the green colour
- A little bigger for new players: icon size 48 (was 44) and bar thickness 16 (was 14); your own sizes stay as they are ("Reset size" goes to the new sizes)

**Full Mana Forever 0.8.4**

- New option under Mana potions: "Sound when ready again" plays a short sound when your mana potion cooldown is over, also in combat (off by default; you hear it once when you switch it on). Three sounds of the addon's own to choose from: Drop and bell, Crystal rise, Glass notes
- The five-second rule counts down in whole seconds (5, 4, 3, 2, 1); new option "Whole seconds" under Five-second rule, switch it off for tenths
- On the unlocked frame only icons you carry glow; grey placeholders do not

**Full Mana Forever 0.8.3**

- Profiles: all characters share one set of settings ("Shared"), or a character uses its own ("This character", switch at the top of the settings). Its own settings start as a copy of the shared ones and are kept when it switches back. "Profiles..." copies another character's settings (with class colour, level and last login), resets the profile in use or deletes the settings of characters you no longer play; each asks first, and the last change can be undone until you log out. Also `/fmf profile`. Your settings so far become "Shared", so nothing changes until you choose. Language and own items stay the same for every character; switched-off items belong to the profile
- `/fmf hold` now holds mana potions only until the end of the next fight (or the one you are in) and then releases them by itself, with a chat line. While held, the potion icon is grey and says "HOLD" (shrunk to fit the icon) instead of disappearing; the settings show "on hold" for the potion group. The unlocked frame shows the potion without it. Tip: put `/fmf hold` in a macro. The old `/fmf hold` switched the "Mana potions" group off; if it is still off, switch it on in the settings
- `/fmf test` does the same as `/fmf unlock` (before, it switched a separate test view on and off)
- Switched-off settings show a grey tick instead of a gold one
- Settings: "Drinking" is now "When to light up" (it is about every item, not only potions); the rune's health setting ("Keep health above") sits under Runes and the spells' mana setting ("Light up at mana <=") under Own mana spells, greyed out while their group is off
- Every control in the settings and the item list has a tooltip (each icon group, dropdowns, -/+ buttons, close buttons), also while it is greyed out
- The item list and the profiles window open over the settings, framed in gold; the settings are dimmed until you close them, so no window can hide behind another. Esc closes one window per press, the settings last. On its own (`/fmf items`) the item list is a normal window
- The description in the game's addon list says what the addon does, in your game language
- The tip at login appears only on a new install; after an update one line names the new version, otherwise the addon stays silent

**Full Mana Forever 0.8.2**

- Mana regen turns green when it is above your normal rate: out of combat it is compared with your lowest normal regen since the last level-up or gear change (drinking, Spirit Tap, buffs, ...); in combat Forever hides the value from addons, so only your own Evocation (8 s) and Ley Line reading (15 s) count
- The mana numbers, the five-second seconds and the regen also show with the mana bar switched off
- New setting "Move texts freely" (next to "Unlock frame", usable while the frame is unlocked): drag the mana numbers, the five-second seconds and the regen anywhere, each on its own; `/fmf reset` puts them back at the bar
- The mana numbers have their own switch and text size, like the five-second rule and the regen; "None" left the list (an old "None" becomes the switched-off mana numbers)
- Settings: "Reset size" sits next to "Reset position"; settings of a part that is switched off (mana bar, mana numbers, five-second rule, regen) stay in place, greyed out

**Full Mana Forever 0.8.1**

- While you shoot a wand the game blocks items for a moment after each shot: the potion icon now stays lit and shows that short wait as a sweep, like the action bar (the potion fits, stop shooting and drink). The spell icon shows the same wait (the game locks spells too) and no longer hides for it out of combat. Only wands do this; bows and melee swings put no wait on items
- Auto bar length: room only for the icon groups you switched on (at least 3 icons); switching a group on or off in the settings resizes the bar at once
- Nothing is shown while your character is dead or a ghost (the unlocked frame still shows, to place it)
- Removed the one-time clean-up of the old FMF_* macros from 0.6.6 (it ran at every login); a macro left over from then can be deleted by hand
- Own spells, never shown as ready too early: every spell's cooldown is read before a fight (before, only the first ready one's, and none with "Show only in combat"); a spell whose cooldown was never read waits until after the fight; a cast of a lower rank counts too; Inner Focus's cooldown starts when its buff is used
- Life Tap is only shown once its mana is known, so it always has the health check; its mana is read again after fights and gear changes
- A potion's own cooldown is remembered, so a wand shot reported on top of it cannot make it look ready
- The marker of the spell slot follows the spell the icon shows; the settings name the spell that comes back first
- Settings: "Spells at mana <=" without an extra colon; Portuguese: Life Tap is "Tributo de Vida"
- Icons: the light on top now fades out downwards; the hard line in the middle made icons look half full
- Log (`/fmf log on`): every spell your group casts with the caster's name (spells that help with mana every time, others once per class), who is in the group, and `/fmf log chat` also tests an invisible addon message to the group
- Less work per update (no new table for the mana percentage, spell icons cached, no cooldown reads in combat)

**Full Mana Forever 0.8.0**

- New: your own mana spells get an icon slot, like the consumables: Evocation (mage), Innervate (druid, on yourself), Mana Tide Totem (shaman), Inner Focus (priest), Life Tap (warlock) and the racials Eureka! (gnome) and Ley Line reading (Skyborne). A spell lights up when it is ready and your mana is at or below "Spells at mana" (50 % by default), shown by a turquoise marker on the mana bar. Life Tap lights up like a potion when its mana fits and keeps the same minimum health as runes
- Fixed: potions and other items no longer disappear while you shoot a wand or cast; the short global cooldown the game puts on items too was taken for the item's own cooldown
- In combat Forever hides spell cooldowns from addons, so the addon counts them from your own cast; out of combat it reads them exactly. A spell is never shown as ready too early
- The log also records group members' Innervate and Mana Tide; `/fmf log chat` tests whether the addon may send chat and addon messages

**Full Mana Forever 0.7.1**

- Icons in a row: the mana numbers sit outside the bar, on the side away from the icons (below the bar when the icons are above it, and the other way round), so markers and the five-second strip no longer cover them
- Icons in a row: the five-second seconds sit left of the bar, so they no longer cover the mana numbers at large text sizes
- Icons in a column: with the frame unlocked, the "Full Mana Forever" label moves above the five-second seconds
- Settings: "Lock frame" and "Test mode" are one switch now, "Unlock frame (test mode)": it makes the frame movable and shows everything that is switched on. `/fmf test` does the same as `/fmf unlock`
- For bug reports the log also records spell cooldowns, current mana costs, maximum health and the cooldowns of your mana potions
- Safety: a rune is hidden when the game does not report your maximum health (no health check means no risk)
- Safety: an item whose cooldown has not started yet is never shown as ready (in Forever potion cooldowns start at once, so a potion comes back after 2 minutes, also in the same fight)
- The regen text turns gold during the five-second rule even when the gold strip is switched off
- Settings: "+" on a bar length shorter than one icon makes the bar longer instead of switching to auto
- Settings: dropdowns near the bottom of the screen open upwards instead of off screen
- Item list: equipped gear is recognised the same way as by the icons
- Less work in raids: only your own casts are watched
- `/fmf log on` with a full log says so instead of claiming to record
- In-game help lists `probe 5sr` and `log on|off|clear`; Russian texts use one form of address

**Full Mana Forever 0.7.0**

- New: five-second rule on the mana bar. After a spell that costs mana, a thin gold strip and the seconds at the end of the bar count down the 5 seconds of reduced regen. Wands, potions and food do not start it.
- New: the mana regen running right now, per second, under the mana numbers ("14.8/s"). During the five-second rule it turns gold and shows what still runs while you cast: 0 without talents, more with talents, Innervate or gear. It also works in combat.
- New: mana text like the game's "Status Text": numeric value, percentage, both or none.
- New: `/fmf log on` / `off` records what the game reports (casts, mana costs, regen) for bug reports.
- The five-second rule and the regen can be switched off under "Mana bar with markers", and both have their own text size (60–200 %). "Reset size" resets these text sizes too.
- Test mode and an unlocked frame show the five-second rule too (it runs in a loop), so it can be seen and placed.
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
