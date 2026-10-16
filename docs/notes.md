# Full Mana Forever – development notes

Detailed history behind the rules in `CLAUDE.md`: in-game logs, store metadata, older owner
decisions. Read the part you need; `CLAUDE.md` holds the short version.

## Store and repo metadata (set by hand by the owner)

- The owner uploads to CurseForge by hand, release type **Release**.
- CurseForge summary (short description): at most 256 characters. Since 10 Oct 2026 (248): "Never
  waste a mana potion again: the right potion, rune, mana gem or mana spell (Evocation, Innervate,
  Mana Tide) lights up when it is ready and fits your missing mana. Mana bar with five-second rule
  and live regen. For every WoW Forever mana user." (owner: not only healers). CurseForge
  categories: main HUDs; additional Healer, Caster, Bags & Inventory, Combat. Avatar: own flask
  with an infinity sign. GitHub About (set by hand): "World of Warcraft: Forever addon for healers
  and every mana user: lights up your mana potion, rune, mana gem or own mana spell (Evocation,
  Innervate, Mana Tide...) the moment it is ready and fits your missing mana. Mana bar with the
  five-second rule (5SR) and live mana regen, also in combat. 9 languages."; 16 topics incl.
  wow-forever, classic-plus, five-second-rule; social preview = docs/images/social-preview.png.
  Gallery image descriptions: also at most 256.
- GitHub release: tag `vX.Y.Z` on the release commit, not a pre-release, same changelog text
  and zip. Title "Full Mana Forever X.Y.Z – WoW Forever mana addon"; body = two-line pitch,
  install line (CurseForge app or unzip into Interface/AddOns), the changelog, bug-report link.
  `docs/images` (README images, social preview) is not part of the addon zip. This session cannot push tags; the owner creates the tag with the release.


## Facts about Forever and decisions, in the order they came up

- Mana regen is continuous (retail engine), no 2-second ticks; the five-second rule still exists.
- Spirit regen in combat was reworked; talents keep part of it while casting (Meditation,
  Spirit Tap, Reflection, Bestial Discipline). Exact numbers unknown.
- Innervate (Druid, level 40, 6 min cooldown, 20 s): +400% mana regen of the target and 100% of
  it continues while casting. The beta is capped at level 30, so it cannot be tested there.
- Unknown until the in-game log (`/fmf log on`) answers: whether `GetPowerRegen`, spell costs
  and player buffs are secret in combat.
- First log (priest 16, beta): out of combat `GetPowerRegen` is readable (base 14.75/s, casting
  0.00); from the first second of combat both values are SECRET. Spirit Tap: base 23.25,
  casting 11.63 (50 % keeps running while casting). Spell IDs and mana costs from
  `UNIT_SPELLCAST_SUCCEEDED` + `C_Spell.GetSpellPowerCost` are readable in combat and include
  cost reductions (Eureka); wand Shoot, food and potions report no cost. The aura list
  (`GetAuraDataByIndex`) is empty in combat. `UNIT_POWER_UPDATE` for mana fires only a few
  times per 10 s.
- Second log: in combat `GetAuraDataByIndex` errors and `GetPlayerAuraBySpellID` returns nil
  even while Spirit Tap is active (it was active in combat in both logs; regen right after
  combat is 23.25). Buffs are invisible to addons in combat. A secret regen value can be
  formatted with `string.format` and put into a FontString (`text=ok`). `GetManaRegen` is the
  same as `GetPowerRegen` (secret in combat). Mana potions show up as casts without cost
  (Restore Mana 438), so they never start the five-second rule.
- Third log (0.7.0 first version): the five-second countdown matches the casts exactly; wand
  and procs (Eureka!) do not start it. x5 of a secret regen through a linear curve reported
  "broken" from the first sample, possibly because the very first try right after login hit
  a briefly secret value; since then it is retried every 10 s and the reason is logged.
- Decision (owner): the bar shows only the regen running right now, per second, in and out of
  combat (x5 to mp5 is impossible on secret values); the rule's seconds sit at the end of the
  bar. The x5 curve attempt was removed.
- Fourth log: `Curve:Evaluate` refuses a secret argument ("Usage: local y = self:Evaluate(x)"),
  so mp5 in combat is impossible; per second stays, no mp5 option. "/с" showed as a box: the
  cause was `OutlineFont` setting a single font file (Latin only) instead of the game's font
  family. Text with letters must use the game's "...Outline" font objects or stay as is.
- `CurveConstants.ScaleTo100` exists in Forever: `UnitPowerPercent(..., ScaleTo100)` gives the
  mana percentage (shown in game as 58 %, 69 %).
- Fifth log (0.7.1, priest 17): max health is readable in combat (`UnitHealthMax` = 332), so the
  rune's HP check works there. Item cooldowns are readable in combat and work like Classic: a
  mana potion drunk in combat starts its 2-minute cooldown at once (`enable` 1) and is ready
  again in the same fight. Spell cooldowns (`C_Spell.GetSpellCooldown`) are SECRET in combat
  and readable out of combat — for 0.8.0, spell readiness cannot be read in combat. The
  potion cast in this log was Restore Mana 437 (no cost).
- Scans for 0.8.0 (owner's private tooling): the spell book
  does not list spells of later levels. `GetSpellBaseCooldown` works for any spell ID, also
  unlearned ones. Talents: the old talent API is gone; `C_ClassTalents.GetActiveConfigID` +
  `C_Traits` read the talent tree with ranks (priest: 54 talents). Other addons' tables are
  hints only, never copied.
- Mana spells in Forever (ID, level, base cooldown s): Innervate 29166 (druid 40, 360; +400 %
  regen, 100 % while casting, 20 s), Evocation 12051 (mage 20, 480; +1500 % for 8 s, channeled),
  Mana Tide Totem 16190/17359 (shaman, 300; group, every 3 s for 12 s), Life Tap 1454/11689
  (warlock 14, no cd, health to mana; not tested in game yet), Mana Spring Totem 5675/10497, Blessing of Wisdom 19742/19854
  and Greater 25894/25918, Seal of Wisdom 20166/20357, Lay on Hands (paladin 10, 1200;
  Forever rank 1, owner's Wowhead screenshot: heals for the paladin's max health and USES all
  remaining mana, no cost entry, does not stop regen. Rank 2 2800 (level 30) restores 250, rank 3
  10310 (level 50) 550 mana of the TARGET (Classic IDs, unconfirmed in Forever): never a source for the paladin's own slot, but a group helper like
  Innervate for 0.9.0; it is on the group log's watch list), Mage Armor 6117/22783 (50 % regen while casting), Totemic Recall 36936 (25 % of
  totem mana back), Drain Mana 11704, Viper Sting 14280. Talents/procs: Inner Focus 14751 (180,
  next spell free), Omen of Clarity 16864, Meditation 14521, Spirit Tap 15270.
  Racials: Gnome Eureka! 1259823 (120; next 3 spells 10 % cheaper), Expansive Mind 20591 (+5 %
  max mana); Skyborne (new race) Ley Line reading 1259705 (+100 % health and mana regen, 15 s or
  15 min near a ley line); Human Spirit 20598 (+5 % spirit). Racial priest spells (Desperate
  Prayer, Starshards, Feedback, ...) have nothing to do with mana.
- Decision (owner, 0.8.0): show which group members have Innervate / Mana Tide ready and who
  they are (in raids people ask by voice). Whispering a request is only an option, off by
  default. Waiting on a log: are group members' spell IDs readable in combat, and may an addon
  whisper / send addon messages in combat (`/fmf log chat`). The beta cap (30) rules out Innervate
  and Mana Tide, so since 0.8.1 the log names every spell the group casts (mana helpers like
  Blessing of Wisdom, Mana Spring, Arcane Intellect, Divine Spirit, Conjure Water every time,
  others once per class), the caster's name and the roster.
- CurseForge gallery (owner, 0.7.x): 1280x720 images made by `tools/gallery.py` from in-game
  screenshots (English addon texts, PNG). Done: hero, right potion, five-second rule (row and
  column), mana text, item list, unlocked frame. For 0.8.0 (made, hand over with the release
  when the owner asks): 09_own_spells (new), 08_unlocked (5 icons) and 06_settings (two halves)
  replace the 0.7.0 ones on CurseForge. All row images were re-shot with the 0.8.x bar (0.8.1/0.8.2
  uploads); every image on CurseForge is current as of 0.8.2.
- 0.8.7 (14 Oct): 06_settings (entry 06v4) and 07_item_list (entry 07v2, "Items and spells" with
  the own spells) re-made from the owner's English screenshots.
- 0.8.9 gallery (16 Oct, owner's shots of 0.8.10 at icon size 72, bar 20, whole seconds; entries
  v9-* in tools/gallery.py): 01, 02, 03 row and column, 07, 08, 09, 10 (with red), 11 re-made,
  14_see_it_coming new. GIFs in docs/images (see-it-coming-mana-potion.gif,
  five-second-rule-live-regen.gif, from two short screen recordings, cropped to the addon) are
  linked in the description. Order on CurseForge from 0.8.9: hero, see it coming, regen at a
  glance, right potion, rule row, rule column, own spells, items and spells, easy to place, move
  texts, just the regen, mana text, profiles and hold, settings. Featured: hero, see it coming,
  regen at a glance, right potion, own spells.
- The finished gallery images (as on CurseForge) are kept in `docs/gallery/`. The in-game source
  screenshots are NOT in the repo (they show character names and chat): the owner keeps them;
  `tools/gallery.py` expects them as `<workdir>/images/<n>.webp`, numbers from the old session.
- Gallery workflow (owner): images are updated as the addon changes. When a change alters what
  a gallery image shows, ask the owner for screenshots during development or at the latest with
  the GitHub release, and prepare the images (`tools/gallery.py`, descriptions <= 256) then.
  On CurseForge since 0.8.2: 12 images in this order: hero ("Drink at the right moment"), regen at a
  glance, right potion, rule row, rule column, just the regen, move texts, mana text, item list,
  easy to place, own spells, profiles and hold (13, since 0.8.3), settings (0.8.3 window). Featured (star, under the description): hero, regen at a
  glance, right potion, rule row, own spells.
- Idea for 0.8.1: the player frame of the game shows predicted mana (the cost of the cast in
  progress is already taken off); the addon uses the real value, so an icon lights up only when
  the cast lands. `UnitPowerPercent(..., predicted=true)` could light it up during the cast;
  risk: a flicker when the cast is interrupted. Decision (owner, 0.8.1): keep the real value.
- Decision (owner, 0.8.1): the auto bar length counts only groups that are switched on (and the
  class can use), minimum 3; lit icons never change it.
- Sixth log (0.8.0, priest 19): every wand Shot puts a cooldown of the weapon speed (1.8 s) on
  all items (`GetItemCooldown` = start+1.80, enable 1); casts did not. Counting it hid every
  potion while wanding; cooldowns of 3 s or less are now ignored for items (fixed in 0.8.0).
  The owner confirmed the game really blocks potions for those 1.8 s (cooldown swipe on the
  button). Decision: the icon still shows while wanding — it means "the potion fits, stop
  shooting and drink"; hiding it would hide every potion as long as the wand keeps firing.
  0.8.1: the icon shows that wait as a cooldown sweep; the owner saw the same lock on spells, so
  the spell icon borrows the last short item cooldown for its sweep (spell cooldowns are secret
  in combat) and Spells.lua ignores read spell cooldowns of 5 s or less; the limit is 5 s (owner, 0.8.1: melee
  swings (dagger, priest) and a bow put no cooldown on items; only wands do).
- 0.8.1 review: unverified in game — whether `C_Spell.GetSpellCooldown` reports `isEnabled =
  false` for Inner Focus while its buff is up (the addon also waits for the next mana spell
  itself). Ley Line reading: 2 min cooldown (owner, from the game tooltip), now `cd = 120` in
  Data.lua (kept as a fallback). Seventh log (0.8.1, Skyborne mage 5): `GetSpellBaseCooldown`
  reports 120 for it; cast in combat with no cost, cooldown SECRET in combat; the icon hid after
  the cast. The racial "Walk on Air" 1259416 (120) has nothing to do with mana.
- 0.8.2 (user request on CurseForge, owner: "do all"): regen text green when above normal
  (out of combat vs the lowest normal regen since the last level-up or gear change, +10 %; in
  combat only own Evocation 8 s and Ley Line reading 15 s, Innervate left out because its
  target is unknown). All three texts (mana numbers, rule seconds, regen) show without the bar
  and can each be dragged (`textFree`, `textPoints[mana|fsr|regen]` in screen units, reset by
  `/fmf reset`); the owner read the request as "move all texts".
- Eighth log (0.8.2, gnome priest 20): drinking (Drink 431) IS part of `GetPowerRegen` (base 15.50
  -> 36.30, casting 0.00 -> 20.80), so the regen turns green while drinking. In game (owner):
  Refreshing Spring Water (145 mana / 18 s) showed 23.9/s green (15.5 + 8.4), and 8.4/s gold when
  sitting down to drink right after a spell (casting itself stands you up and ends the drink):
  the drink adds to the regen and keeps running during the five-second rule. The Forever buff
  "Thrill of Adventure" 1261483 (renamed from "Adventurous Thrill", build 70374) is NOT part of it (36.30 with and without it). It comes from a
  passive talent of the new "Adventures" tree: after a kill that gives XP or honor, 1 % of max
  health and mana over 10 s at rank 1/5 (2 % at rank 2), not in dungeons, raids or battlegrounds.
  Not coloured (green would then show a normal number); maybe later a "+x" out of combat.
- Forever patch notes (owner, 0.8.2 time): druids may drink mana potions in forms (the addon never
  checks forms; untested whether mana stays readable in bear/cat form); Seal of Fury restores mana
  only with Improved Seal of Fury (no paladin source in the addon, only the Diag watch list);
  Mana Tide and Water Shield changed only visuals. Blizzard's Cooldown Manager now shows trinkets,
  consumables "later": overlaps with "potion is ready", not with "fits your missing mana", runes'
  health check, own spells, five-second rule and regen. Watch it.
- UX review for 0.8.3 (three reviewers, owner decisions): 0.8.3 = per-character profiles +
  confirmed bugs + settings order/wording; 0.8.4 = HUD polish (colour system: white markers inside
  the bar, gold only for the five-second rule; Blizzard-like ready glow; gradient bar gloss; digit
  font, whole seconds; non-colour cue for regen states; bigger defaults). Profiles: saved
  variables stay account-wide (copying needs it); "Shared" + own per character (created as a copy
  of Shared, kept when switching back); new characters start on Shared; switch in the window title,
  rare actions (copy / reset / delete stale) in a small "Profiles..." window; copy and reset
  confirm, one undo per session; disabled items per profile, own items and language account-wide;
  profiles keyed by name so named profiles can come later. Every module must re-read the active
  profile on a switch (Core caches `db`). "Drinking" becomes "When to light up" (all languages).
  `/fmf hold` (command / macro only, owner: no key binding): its own state, not the "Mana
  potions" switch; ends at the end of the next fight; while held the potion shows grey with
  "HOLD" when it would light up; a second /fmf hold ends it early.
- Launch plan (owner, 0.8.3 time): Forever beta ends 21 Oct 2026, launch 4 Nov (EU 5 Nov). By 21 Oct
  the most stable and complete version must be out; at launch only the Interface number (check
  the live client, 16001 may change) and bug fixes. SEO (three reviews, owner decisions): keywords
  WoW, WoW Forever, World of Warcraft: Forever, Classic Plus / Classic+; "mana tick" and "mp5" ARE
  used, but only in their true context (Forever has no ticks, mp5 is impossible in combat; the
  addon shows the live regen per second instead); never claim Classic Era / retail support. No
  user names (e.g. commenters) in texts; "features asked for in the comments get built" is fine.
  CurseForge avatar: own flask with an infinity sign (no new logo needed). 9 languages (esMX uses
  the esES texts), not 10.
- Litany of Light (Forever priest talent, owner's Wowhead screenshot): a healing spell gives back
  20 % of its base cost if the previous heal was a different spell. Instant mana after the cast,
  no regen and no buff: the addon sees it as normal mana; nothing to build for it.

- Character names (owner, 11 Oct, beta): one big server per region, no realms to choose.
  `UnitName("player")` and `UnitFullName("player")` return the first name and then the
  **surname** (where other clients return the realm); `GetRealmName()` returns the beta server's
  name. Profile keys are therefore "First Surname-Realm" (0.8.6; before only the first name).
  The realm name may change at launch, which would give characters new keys (beta characters
  probably do not carry over anyway).

- Mana spells checked in Forever (12 Oct, all mana classes): `GetSpellLevelLearned` gives
  Evocation 20, Innervate 40, Life Tap 6 (rank 1; 11689 rank 6 at 56), Mana Tide Totem 25 (talent;
  Classic had 40), Inner Focus 0 (talent: no level). Ley Line reading is "Read Ley Line"
  (1259705). Dark Pact (18220) does not exist in Forever. Other active mana spells found are buffs
  to keep up (Water Shield, Mana Spring Totem, Blessing/Seal of Wisdom, Mage Armor), mana drains
  (Drain Mana, Viper Sting, Mana Burn) or conjured gems: none fits "ready, then lights up".
- Items found that the addon does not list yet: Combat Mana Potion 18841 (same spell as Superior
  Mana Potion), Mageblood Elixir 20007 (regen elixir), mana oils, EZ-Thro Mana Bomb 260818 (new,
  text not loaded yet), Crisp Spring Water 252031 (new water). The first item pass missed slow
  texts; a second pass is needed before adding numbers.

- Resurrection Sickness on Forever (owner's /dump, 14 Oct): aura 15007, 600 s, readable out of
  combat with `C_UnitAuras.GetPlayerAuraBySpellID(15007)`. `UnitStat("player", 5)` under it:
  38, 38, 26, -36 (effective 38 = base 48 + 26 from buffs - 36): the cut is 75 % of the base.
- Item check 14 Oct 2026 (build 70374, game API): Major and Superior Mana Draught get the same
  120 s cooldown as the potions when a potion is used (moved to the potion group in 0.8.9);
  Celestial, Arcane and Ley Orb say "Classes: Mage". A second run with a potion drunk: the
  shared potion cooldown also covers Tessa's Tonic, Diet McWeaksauce, Wildvine Potion, Mug of
  Shimmer Stout, Full Moonshine, Restored Mana Potion (20 % of max mana), the Forever copies
  287968/287969 and Windstone (Skywall only, not added); all added in 0.8.9, with Power
  Recycler (20 % health into 20 % mana), Tea with Sugar 15723, Earthen Sigil 20525, Scroll of
  Minor Evocation 213564 (mage) and Veildust Medicine Bag 15866 (druid off-hand).
- Checked 14 Oct 2026 (build 70374): the potion cooldown is one shared 120 s cooldown for 13
  items (all mana, rejuvenation and Dreamless Sleep potions, the draughts, Combat Mana Potion),
  as in `Data.lua`. All our spell IDs and ranks still match (Evocation 20, Mana Tide 25/48/58,
  Innervate 40, Life Tap 6-56). The Adventures talent "Thrill of Adventure" 1225472 gives 5 % of
  max health and mana over 10 s at max rank; a proc, not a button, so no icon.

## From the ManaMaster addon (olav9/ManaMaster, Apache-2.0; its notes, not verified by us)

ManaMaster (CurseForge 1718932) tracks mana spent/saved per fight with a history panel and a
Details plugin; it targets Forever too. Ideas may be used, code only with Apache-2.0 attribution.
Its in-game findings on Forever:
- `GetManaRegen` leaves out Blessing of Wisdom (12 mp5: same rates with and without it, level ~20
  mage); gear mp5 is included, also within the five-second rule. mp5 buffs keep working within
  the rule. So our regen text does not show BoW (and probably Mana Spring): checklist 3a checks it.
- Registering `COMBAT_LOG_EVENT_UNFILTERED` on Forever shows the "blocked action" pop-up; the
  Combat Log tab stores combat lines as protected tokens. No combat log for addons.
- `UnitPower` (mana) secret also out of combat for them. `UnitPowerMax` readable.
- In combat `C_UnitAuras.GetAuraDataByIndex` errors for some buffs ("Auras cannot be accessed when
  secret"); `GetAuraDataByAuraInstanceID` per known instance tells whether a buff is still up.
- They found drinking NOT in `GetManaRegen`; our eighth log shows drinking IS in `GetPowerRegen`
  (15.50 -> 36.30). Our log is first-hand; theirs may be older or a different function.
- Forever loads `<Addon>_Camelot.toc` (Details does); the BigWigs packager knows the `forever` game
  type from v2.6.0. Our plain `FullManaForever.toc` with Interface 16001 loads fine.
