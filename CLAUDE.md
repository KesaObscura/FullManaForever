# Working on Full Mana Forever

WoW: Forever addon (client 1.60.1, interface 16001). Plain Lua 5.1, no libraries.
Files load in TOC order: Locale.lua → Data.lua → Regen.lua → Core.lua → Options.lua →
Library.lua → Diag.lua. Regen.lua: five-second rule and regen text; Diag.lua: `/fmf probe 5sr`
and `/fmf log` (kept in releases for bug reports).

## Rules

- **Public repository: nothing personal.** No `Claude-Session:` links, no `Co-Authored-By:`
  trailers, no e-mail addresses in commits, PR texts, code or docs. Commit messages describe
  the change only.
- **Every user-visible text in all 9 locale tables** of `Locale.lua` (esMX falls back to
  esES). `lua5.1 tests/run.lua` checks keys and placeholders.
- **Run the tests after every change:** `lua5.1 tests/run.lua` must end with `0 failed`.
- **After every change, hand the owner a test zip** built from the committed state:
  `git archive --format=zip --prefix=FullManaForever/ -o FullManaForever-<version>-<hash>.zip HEAD -- . ':!tests' ':!.gitignore' ':!.pkgmeta' ':!CURSEFORGE.md' ':!CLAUDE.md'`
  (same contents as `.pkgmeta` packages).
- Work on the session branch; `main` changes only through a PR the owner merges.

## Keep in sync on every user-visible change

- `CHANGELOG.md`: headings `**Full Mana Forever X.Y.Z**` (no "beta").
- `CURSEFORGE.md`: the project description on CurseForge. Update features, commands and the
  "Tested so far" note; the owner copies it to CurseForge by hand.
- `README.md`: commands table.
- Version in `FullManaForever.toc` and `ns.VERSION` in `Core.lua`.

## Releases

- The owner uploads to CurseForge by hand, release type **Release**.
- CurseForge summary (short description): at most 256 characters. Current one (since 0.7.0,
  206): "Shows a mana potion, rune or mana item the moment it is ready and your missing mana is big
  enough that nothing is wasted. Plus a mana bar with the five-second rule and your live mana
  regen. For WoW Forever."
- GitHub release: tag `vX.Y.Z` on the release commit, not a pre-release, same changelog text
  and zip. This session cannot push tags; the owner creates the tag with the release.

## Facts about Forever (for the regen / five-second-rule feature, 0.7.0)

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
- Scans for 0.8.0 (`/fmf scan`, `/fmf scan trainer` with TrainerSpells installed): the spell book
  does not list spells of later levels. `GetSpellBaseCooldown` works for any spell ID, also
  unlearned ones. Talents: the old talent API is gone; `C_ClassTalents.GetActiveConfigID` +
  `C_Traits` read the talent tree with ranks (priest: 54 talents). TrainerSpells is "All Rights
  Reserved": never copy its data or code into this repo; it is read only at run time.
- Mana spells in Forever (ID, level, base cooldown s): Innervate 29166 (druid 40, 360; +400 %
  regen, 100 % while casting, 20 s), Evocation 12051 (mage 20, 480; +1500 % for 8 s, channeled),
  Mana Tide Totem 16190/17359 (shaman, 300; group, every 3 s for 12 s), Life Tap 1454/11689
  (warlock, no cd, health to mana), Mana Spring Totem 5675/10497, Blessing of Wisdom 19742/19854
  and Greater 25894/25918, Seal of Wisdom 20166/20357, Lay on Hands 10310 (paladin, 1200, gives
  550 mana), Mage Armor 6117/22783 (50 % regen while casting), Totemic Recall 36936 (25 % of
  totem mana back), Drain Mana 11704, Viper Sting 14280. Talents/procs: Inner Focus 14751 (180,
  next spell free), Omen of Clarity 16864, Meditation 14521, Spirit Tap 15270.
  Racials: Gnome Eureka! 1259823 (120; next 3 spells 10 % cheaper), Expansive Mind 20591 (+5 %
  max mana); Skyborne (new race) Ley Line reading 1259705 (+100 % health and mana regen, 15 s or
  15 min near a ley line); Human Spirit 20598 (+5 % spirit). Racial priest spells (Desperate
  Prayer, Starshards, Feedback, ...) have nothing to do with mana.
- Decision (owner, 0.8.0): show which group members have Innervate / Mana Tide ready and who
  they are (in raids people ask by voice). Whispering a request is only an option, off by
  default. Waiting on a log: are group members' spell IDs readable in combat, and may an addon
  whisper / send addon messages in combat (`/fmf log chat`).
