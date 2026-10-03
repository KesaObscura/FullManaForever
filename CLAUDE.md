# Working on Full Mana Forever

WoW: Forever addon (client 1.60.1, interface 16001). Plain Lua 5.1, no libraries.
Files load in TOC order: Locale.lua → Data.lua → Core.lua → Options.lua → Library.lua.

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
  so mp5 in combat is impossible; per second stays, no mp5 option. A string built by
  `string.format` from a secret value mangles multibyte letters ("/с" showed as a box):
  format only the number, put localized units in a separate plain FontString.
