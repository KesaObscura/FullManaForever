# Working on Full Mana Forever

WoW: Forever addon (client 1.60.1, interface 16001). Plain Lua 5.1, no libraries.
Files load in TOC order: Locale.lua → Data.lua → Regen.lua → Spells.lua → Profiles.lua → Core.lua →
Options.lua → Library.lua → Diag.lua. Spells.lua: own mana spells (0.8.0). Profiles.lua (0.8.3):
`FullManaForeverDB` holds account keys (language, custom, debug, scale100, seenVersion, dbVersion)
plus `profiles[Shared|Name Surname-Realm]` and `chars[key]` = {profile, class, level, seen, name, realm}; Core's
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
- Work on the session branch; `main` changes only through a PR the owner merges with **Squash
  and merge** (owner, 15 Oct: no merge commits with the branch name in `main`); after the merge
  reset the session branch to `main`.
- Commit author stays `Claude <noreply@anthropic.com>` (owner, 15 Oct); never rewrite the history
  of `main`. `CLAUDE.md` stays in the repo (cloud sessions read it from there).

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
  Drinking is part of `GetPowerRegen`; "Thrill of Adventure" (was "Adventurous Thrill") is not.
- `GetSpellBaseCooldown` and `C_Spell.GetSpellLevelLearned` (Evocation 12051 -> 20) work for
  any spell ID; talents via `C_ClassTalents` + `C_Traits`.
- Research data comes from the owner's private tooling, not from this addon: never add scan
  commands here or describe them in public texts. Only single facts we need, checked against
  the game's own API, go into `Data.lua` (no bulk copies of other addons' tables or code).
- Mana spell IDs, ranks and cooldowns: `Data.lua` and `docs/notes.md`.

## Owner decisions in force

- Real mana value, not the predicted one (icons light up when the cast lands).
- Auto bar length counts only groups switched on (and usable by the class), each own spell that
  can get an icon (0.8.7, owner: icons must not run past the bar), minimum 3.
- The potion icon stays lit while wanding (sweep shows the wait).
- Regen green when above normal (out of combat vs the lowest normal regen since the last
  level-up or gear change, +10 %; in combat only own Evocation 8 s and Read Leyline 30 s, owner 17 Oct).
- Profiles (0.8.3): "Shared" + own per character (copy of Shared, kept when switching back); new
  characters start on Shared; copy/reset/delete confirm, one undo per session; disabled items
  per profile, own items and language account-wide.
- `/fmf hold`: own state (not the potion switch), ends after the next fight, potion shown grey
  with "HOLD", not on the unlocked frame; command/macro only, no key binding.
- 0.8.3 also: "Drinking" becomes "When to light up" (all languages). 0.8.4 (after launch): HUD
  polish (colour system, Blizzard-like glow, bar gloss, digit font, bigger defaults).
- Group features (after launch; were planned as 0.9.0): who has Innervate / Mana Tide ready;
  whispering only optional.
- 0.9.0 (owner, 17 Oct): the patch research, the item review and everything a CurseForge comment
  asked for to work with unit frame addons: texts above the bar, "Above other frames" (HIGH
  strata), "Seconds" switch, smooth five-second strip, "Only markers" bar style, "Move the bar
  separately" (`barFree`, `barPoint`), mana fill eased via `Enum.StatusBarInterpolation` when
  the game has it.
- Texts and SEO: keywords WoW, WoW Forever, World of Warcraft: Forever, Classic+; "mana tick" and
  "mp5" only in their true context (Forever has none, the addon shows live regen); never claim
  Classic Era / retail support; no user names in texts ("features asked for in the comments get
  built" is fine); 9 languages, not 10. Not only for healers: every mana user.
- Launch: beta ends 23 Oct 2026 (extended from 21 Oct), launch 4 Nov (EU 5 Nov). By the beta end the most stable, complete
  version; at launch only the Interface number (16001 may change) and bug fixes.

## Roadmap and reminders (owner asked to be reminded; keep this list current)

1. Done: 0.8.3 profiles tested by the owner; settings order and wording (step 3) shipped.
3. Released on GitHub: 0.8.3, 0.8.4 (10 Oct), 0.8.5 and 0.8.6 (11 Oct), 0.8.7 (14 Oct, items and
   spells list, tested by the owner), 0.8.8 (14 Oct, icons before ready); 0.8.9 ready (regen after death, items from the
   game's own cooldowns, percent amounts), tested by the owner 14 Oct. CurseForge uploads by
   the owner: 0.8.3 on 11 Oct (description CURSEFORGE.md, gallery 06_settings replaced,
   13_profiles_hold new), 0.8.4 on Monday 12 Oct, 0.8.5 on 13 Oct, 0.8.6 on 14 Oct (description:
   /fmf profile copy with the surname), 0.8.7 on 15 Oct (new description in three blocks with
   images linked from GitHub: they show on CurseForge; gallery 06 and 07 new), 0.8.8 on 16 Oct (description
   with "See it coming", gallery unchanged); 0.8.9 next, with new screenshots and a GIF (owner
   records video). 0.8.10 released on GitHub 16 Oct (own icon, minimap menu tooltip, gallery and GIFs);
   0.8.11 released on GitHub 17 Oct (icon order without gaps, - / + fix, gallery 12); 0.9.0
   released on GitHub and CurseForge 21 Oct (unit frame options, item review, Read Leyline 30 s;
   CurseForge changelog covered 0.8.10-0.9.0). Before the beta end (23 Oct): two more releases,
   the first from the three UX reviews (HUD, settings, first run). CurseForge (history):
   0.8.9 is the last upload; 0.8.10 and 0.8.11 were skipped there (owner, 21 Oct): 0.9.0 goes up
   next with one changelog covering 0.8.10, 0.8.11 and 0.9.0, released together on GitHub. PR bodies: check after creating
   that no session link was appended (removed from PR #1-#15 on 16 Oct).
3d. 0.8.12 (owner, 17 Oct): research after the 17 Oct patch (talents, abilities, spells) and the
   item review: what is junk / unimportant for the addon, what is needed. Everything found but not
   taken is kept in the owner's private research notes and decided again after every scan.
   First pass done 17 Oct (facts in `docs/notes.md`); item data not complete even after a
   second pass: ~7 400 item IDs are still refused by the beta server (also real items such as the
   trinkets Second Wind 11819 and Burst of Knowledge 11832): look again after launch. Decided
   17 Oct: Read Leyline 30 s (0.8.12), Windstone is junk. Item review done 21 Oct (0.9.0, see
   `docs/notes.md`).
3c. Done in 0.8.11 (owner, 17 Oct: option C, no setting): icons sorted by the threshold they
   light up at (`ByLight` in `ns.Layout`), health-checked icons last only on equal thresholds.
   Tested in game by the owner 17 Oct. The order is dynamic (thresholds, max mana): the gallery
   stays as it is (owner, 17 Oct); only "Just the regen" (12) is re-shot for 0.8.11.
3b. 0.8.6: the three-agent code review done; its fixes (8 bugs, 3 speed items) without changing
   what the addon does, each with a test that fails on the old code. Left out on purpose:
   secret nil comparisons, longUntil d==0, OwnedItem caching. Also: character keys with the
   surname (owner's /dump: UnitName("player") returns first name and surname; GetRealmName is the
   beta server's name).
   Tested in game by the owner (all fixes) except the surname keys.
4. Owner (17 Oct): no listing requests on other sites (foreverchanges.pro, Wago, WoWInterface
   dropped): the addon goes its own way. Features until the beta ends, each tested in game.
   0.8.10 tested in game (icon, menu tooltip, right-click). 0.8.11 started 17 Oct: icon gaps
   (3c), re-shoot "Just the regen", then the GitHub release; item review moved to 0.8.12. GitHub allows squash merging only.
5. Launch 4 Nov (EU 5 Nov): check the Interface number of the live client (16001 may change),
   fix bugs, reply to CurseForge comments within 1-2 days. No promotion posts (owner, 17 Oct:
   Blizzard forum, Reddit and notes to other sites dropped; the addon goes its own way).
6. Untested in game: owner's printed list `docs/test-checklist.md`: group log (owner records it
   next), launch-day Interface check; other classes (druid forms, Life Tap, Mana Agate, Evocation)
   when the owner has a character of that level, or from users. Inner Focus tested 17 Oct.
7. 0.8.4 (owner: one release per day until 21 Oct): whole seconds, sound when the potion is
   ready again (option, off), no glow on placeholders. Gallery images 03 (rule row/column) and 10
   show tenths of seconds: re-shoot when convenient. Rest of the HUD polish and the group features
   after launch; they need the group log first. Maybe Wago / WoWInterface mirrors later.
