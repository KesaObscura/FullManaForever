# Working on Full Mana Forever

WoW: Forever addon (client 1.60.1, interface 16001). Plain Lua 5.1, no libraries.
Files load in TOC order: Locale.lua → Data.lua → Regen.lua → Spells.lua → Profiles.lua → Core.lua →
Options.lua → Library.lua → Diag.lua. Spells.lua: own mana spells (0.8.0). Profiles.lua (0.8.3):
`FullManaForeverDB` holds account keys (language, custom, debug, scale100, seenVersion, dbVersion)
plus `profiles[Shared|Name-Realm]` and `chars[Name-Realm]` = {profile, class, level, seen}; Core's
`db` is the active profile, `acct` the root; `ns.ApplyProfile` re-reads everything on a switch. Regen.lua: five-second rule and regen text; Diag.lua: `/fmf probe 5sr`
and `/fmf log` (kept in releases for bug reports).

## Rules

- **Public repository: nothing personal.** No `Claude-Session:` links, no `Co-Authored-By:`
  trailers, no e-mail addresses in commits, PR texts, code or docs. Commit messages describe
  the change only.
- **Every user-visible text in all 9 locale tables** of `Locale.lua` (esMX falls back to
  esES). `lua5.1 tests/run.lua` checks keys and placeholders.
- **Every control that can be clicked has a tooltip** (owner, 0.8.3), also while greyed out
  (`Tip` sets `SetMotionScriptsWhileDisabled`); a test walks all controls of the settings and
  the item list.
- **Run the tests after every change:** `lua5.1 tests/run.lua` must end with `0 failed`.
- **After every change, hand the owner a test zip** built from the committed state:
  `git archive --format=zip --prefix=FullManaForever/ -o FullManaForever-<version>-<hash>.zip HEAD -- . ':!tests' ':!tools' ':!docs' ':!.gitignore' ':!.pkgmeta' ':!CURSEFORGE.md' ':!CLAUDE.md'`
  (same contents as `.pkgmeta` packages).
- Work on the session branch; `main` changes only through a PR the owner merges.

## Keep in sync on every user-visible change

- `CHANGELOG.md`: headings `**Full Mana Forever X.Y.Z**` (no "beta").
- `CURSEFORGE.md`: the project description on CurseForge. Update features, commands and the
  "Tested so far" note; the owner copies it to CurseForge by hand.
- `README.md`: commands table.
- Version in `FullManaForever.toc` and `ns.VERSION` in `Core.lua`.

## Releases

- The owner uploads to CurseForge by hand, release type **Release**, game version 1.60.1.
- CurseForge summary and gallery descriptions: at most 256 characters each. The current summary,
  categories, GitHub About/topics and the gallery order are in `docs/notes.md`.
- GitHub release: the owner creates the tag `vX.Y.Z` (this session cannot push tags); not a
  pre-release; the same changelog text and zip `FullManaForever-X.Y.Z.zip` (no hash). Title
  "Full Mana Forever X.Y.Z – WoW Forever mana addon"; body = two-line pitch, install line
  (CurseForge app or unzip into Interface/AddOns), the changelog, bug-report link.
- Gallery: 1280x720 PNGs by `tools/gallery.py` from the owner's in-game screenshots (English
  addon texts); finished images in `docs/gallery/`. When a change alters what an image shows,
  ask the owner for screenshots. Source screenshots never go into the repo (names, chat).

## Forever facts the code relies on (details and logs: `docs/notes.md`)

- Mana regen is continuous, no 2-second ticks; the five-second rule exists. No mp5 in combat.
- Secret in combat: current mana, `GetPowerRegen`/`GetManaRegen`, spell cooldowns
  (`C_Spell.GetSpellCooldown`), auras (buffs are invisible to addons in combat). Readable in
  combat: max mana, max health, item cooldowns and counts, spell IDs and mana costs of own casts
  (`UNIT_SPELLCAST_SUCCEEDED` + `C_Spell.GetSpellPowerCost`). Out of combat regen and spell
  cooldowns are readable.
- A secret value can only be formatted (`string.format`) into a FontString or turned into an
  alpha by the game (`UnitPowerPercent` with a curve, `CurveConstants.ScaleTo100` exists);
  `Curve:Evaluate` refuses secrets, arithmetic and comparisons fail.
- Text with letters must use the game's "...Outline" font objects (a single font file breaks
  Cyrillic/Asian letters).
- Wands put a weapon-speed cooldown (~1.8 s) on all items after each shot: item cooldowns of
  3 s or less are ignored for readiness and shown as a sweep; spell cooldowns read as 5 s or less
  are ignored. Melee and bows do not do this.
- Potions, food, wand and procs (Eureka!) report no mana cost and never start the rule.
  Drinking is part of `GetPowerRegen`; "Adventurous thrill" is not.
- `GetSpellBaseCooldown` works for any spell ID; talents via `C_ClassTalents` + `C_Traits`.
  TrainerSpells is "All Rights Reserved": never copy its data or code into this repo.
- Mana spell IDs, ranks and cooldowns: `Data.lua` and `docs/notes.md`.

## Owner decisions in force

- Real mana value, not the predicted one (icons light up when the cast lands).
- Auto bar length counts only groups switched on (and usable by the class), minimum 3.
- The potion icon stays lit while wanding (sweep shows the wait).
- Regen green when above normal (out of combat vs the lowest normal regen since the last
  level-up or gear change, +10 %; in combat only own Evocation 8 s and Ley Line reading 15 s).
- Profiles (0.8.3): "Shared" + own per character (copy of Shared, kept when switching back); new
  characters start on Shared; copy/reset/delete confirm, one undo per session; disabled items
  per profile, own items and language account-wide.
- `/fmf hold`: own state (not the potion switch), ends after the next fight, potion shown grey
  with "HOLD", not on the unlocked frame; command/macro only, no key binding.
- 0.8.3 also: "Drinking" becomes "When to light up" (all languages). 0.8.4 (after launch): HUD
  polish (colour system, Blizzard-like glow, bar gloss, digit font, bigger defaults).
- Group features (0.9.0 idea): who has Innervate / Mana Tide ready; whispering only optional.
- Texts and SEO: keywords WoW, WoW Forever, World of Warcraft: Forever, Classic+; "mana tick" and
  "mp5" only in their true context (Forever has none, the addon shows live regen); never claim
  Classic Era / retail support; no user names in texts ("features asked for in the comments get
  built" is fine); 9 languages, not 10. Not only for healers: every mana user.
- Launch: beta ends 21 Oct 2026, launch 4 Nov (EU 5 Nov). By 21 Oct the most stable, complete
  version; at launch only the Interface number (16001 may change) and bug fixes.

## Roadmap and reminders (owner asked to be reminded; keep this list current)

1. Owner tests 0.8.3 profiles in game (blocks everything else).
2. 0.8.3 step 3: settings order and wording (thresholds under their groups, "Drinking" ->
   "When to light up" in all languages); new settings screenshot for the gallery.
3. Release 0.8.3 on 11 Oct (owner: one release per day until the beta ends): merge PR (new README with docs/images goes live), owner tags
   v0.8.3, GitHub release in the new format, new CurseForge description (CURSEFORGE.md); gallery:
   06_settings replaced (0.8.3 window), 13_profiles_hold new (docs/gallery). Then: owner's
   CurseForge author profile (avatar/bio/links) wanted.
4. Before 21 Oct: request a listing on foreverchanges.pro (if they take submissions); 16-20 Oct
   only fixes. 21 Oct (beta end): the most stable and complete version is out.
5. Launch 4 Nov (EU 5 Nov): check the Interface number of the live client (16001 may change),
   fix bugs; one reply in the Blizzard forum thread "WoW Forever Addons" (UI and Macro), one
   Reddit post (check the sub's rules), short notes to Icy Veins / Warcraft Tavern / mein-mmo
   (texts by Claude, sent by the owner). Reply to CurseForge comments within 1-2 days.
6. Untested in game, check when it comes up: druid in forms, Life Tap, group log.
7. After launch: 0.8.4 HUD polish; maybe Wago / WoWInterface mirrors.
