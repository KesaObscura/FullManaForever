# Working on Full Mana Forever

WoW: Forever addon (client 1.60.1, interface 16001). Plain Lua 5.1, no libraries.
Files load in TOC order: Locale.lua → Data.lua → Regen.lua → Spells.lua → Profiles.lua → Core.lua →
Options.lua → Library.lua → Diag.lua. Spells.lua: own mana spells (0.8.0). Profiles.lua (0.8.3):
`FullManaForeverDB` holds account keys (language, custom, debug, scale100, seenVersion, dbVersion, optPoint, probe)
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
  ([CurseForge](https://www.curseforge.com/wow/addons/full-mana-forever) app or unzip into Interface/AddOns), the changelog, bug-report link.
- Gallery: 1280x720 PNGs by `tools/gallery.py` from the owner's in-game screenshots (English
  addon texts); finished images in `docs/gallery/`. When a change alters what an image shows,
  ask the owner for screenshots. Source screenshots never go into the repo (names, chat).

## Forever facts the code relies on (details and logs: `docs/notes.md`)

- Mana regen is continuous, no 2-second ticks; the five-second rule exists. No mp5 in combat.
- Current mana (`UnitPower`) is secret also OUT of combat (notes; 0.9.4 bug in the owner's test,
  6 Nov): "full" or any mana check only through `UnitPowerPercent` with a curve. Tests keep it secret.
- Health is secret also out of combat (Full Health Forever probe, 7 Nov); a secret must not even be
  compared with nil (`IsSecret` / `type` first). Dungeons and raids add restrictions (Map /
  Encounter): FMF in a dungeon (7 Nov): works (owner), max mana readable, curves work; boss fights add
  Encounter and Chat restrictions (addon messages, group features at risk). Details: `docs/notes.md`.
- A NUMERIC curve through `UnitPowerPercent` returns the value as a secret number, printable with
  `string.format` (owner's test addon, 10 Nov): "time to full mana" (0.9.7) uses it.
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
- Regen green when above normal (out of combat vs the lowest regen of the last 5 minutes out of
  combat, 10 parts of 30 s, wiped on level-up or gear change, +10 %; owner 5 Nov, 0.9.3: group
  buffs kept up become normal; in combat only own Evocation 8 s and Read Leyline 30 s, owner 17 Oct).
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
- 0.9.1 (owner, 21 Oct: "all of it" from three UX reviews, HUD / settings / first run): one
  near-white marker colour (shape tells thick / thin), dimmer "soon" icons with one flash when
  ready, calmer glow, white HOLD, rule seconds 130 % by default, settings window at the right edge
  and remembered (`acct.optPoint`), Lock / Settings buttons on the unlocked frame, the bar drags
  the frame, auto-lock when a fight starts, reset buttons ask first, inactive settings greyed.
  Not done on purpose: rule seconds next to the regen (moves everyone's layout), "Show only in
  combat" hiding the regen (owner decision), gallery re-shoots (need screenshots).
- 0.9.2 (owner, 25 Oct: "do it" after three developer reviews, HUD logic / settings and data /
  performance and robustness): fail closed on errors outside the groups (`SafeUpdate` hides all),
  own `pcall` for spells, sound, bar, texts and the spell book at login; `CopyDefaults` replaces
  values of the wrong type, `CleanCustom`, non-table profiles/chars dropped; mana regen only
  (`UnitPowerType`, `GetPowerRegenForPowerType` in forms); `BAG_UPDATE_COOLDOWN` reads potion
  cooldowns at once; `ns.AutoLock` also at login in combat; cooldowns cached per tick; count
  before the level check; the log keeps no names. Guesses left for in-game checks: Clearcasting /
  Inner Focus and the rule, Life Tap with talents, taint from `HideUIPanel(SettingsPanel)`.
- 0.9.3 (owner, 5 Nov: quick fixes from three player reviews): regen norm of the last 5 minutes
  (above), health threshold active for runes, spells (Life Tap) and other items (Power Recycler),
  "Show icons before ready" up to 120 s, potion sound follows "Show only in combat" and the
  solo / party / raid filter, bug link (`ns.BUG_URL`) after help, probe and the first warning,
  log texts without group names, informal "you" in all languages (ru ты, fr tu; de and es were
  already informal; pt-BR "você" is the informal form; ko keeps the polite UI style; zh 你).
- 0.9.4 (owner, 6 Nov: only what a CurseForge comment asked for): "Fade out of combat to"
  (`fadeAlpha`, 1 = off, steps of 10 %) and "Only at full mana" (`fadeFull`, on) for the bar and
  its three texts; out of combat only, "full" by a step curve (`UnitPowerPercent`, half a point
  below max), full at once in combat, back at once; fading out frame by frame over 1.5 s after the
  last reason to show (fight, unlocked frame, with "only at full mana" the last `UNIT_POWER_FREQUENT`
  for MANA: events stop once the mana is full; counted, never read; ignored for 2 s after login); greyed with "Show only in combat"; the unlocked frame never
  fades, the open settings do (owner, 6 Nov: a change must show at once); the first known value after login is taken at once. Reviewed by
  the three player agents (8 / 9 / 8).
- 0.9.5 (owner, 7 Nov: "start 0.9.5"; settings from three UI reviews, owner 7 Nov "do all 4"):
  "Out of combat" list (all / without icons / nothing -> `iconsCombat`, `onlyCombat`; `IconsHidden`
  in Core also for the potion sound); "When it fades" list (full / full also in combat / after a
  fight -> `fadeFull`, `fadeCombat`); "Show icons" (`showIcons`, also markers and sound; groups
  keep their switches, greyed); lists instead of sub-switches for mana text (off -> `manaTextOn`),
  rule seconds (`fsrNum`, `fsrWhole`), bar style (`barStyle`); "Keep health above" under "When to
  light up"; group rows always two lines (no jumping). Saved keys unchanged.
  0.9.6 (owner, 10 Nov: "grow direction and the rest"): "Icons grow" (`iconGrow` normal / reverse;
  reverse: the frame keeps the bar's length, icons from the far end; asked in a comment); typing a
  value by clicking a stepper's number (exact, clamped, % typed as percent; bar length 0 = auto).
  0.9.8 (owner, 10 Nov: release 0.9.6 first, the regroup next; planned 7 Nov): the full regroup of the settings window in two columns (left: position /
  icons / bar / texts, right: when to show / what to suggest, footer: language and resets; see
  the UI reviews), typing a number into a stepper; gallery 06 re-shot after it.
  0.9.7 (owner, 10 Nov; players asked): "Time to full mana" (`fullTimer`, on) out of combat next to
  the regen: a numeric curve over the mana share, piecewise for the five-second rule (casting rate
  first), hidden at full mana by a step curve; not in combat (regen secret, and meaningless while
  casting). The early end of drinking is not foreseen (drink aura IDs unknown): later.
  The settings regroup moves to 0.9.8.
  Later: gallery re-shoots (need screenshots), exact fit to unit frames (sizes typed in / attach
  to the player frame), choice of bar markers (all / potions only / nearest), a "drink" reminder
  between pulls.
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
5. Launch 4 Nov (EU 5 Nov): Interface number checked by the owner on the live client: still
   16001, no "out of date", 0.9.0 works (5 Nov). Launch day: 1 741 downloads, mostly unique.
   0.9.2 (with 0.9.1) released on GitHub 5 Nov (PR #18, tag v0.9.2); CurseForge upload by the
   owner with the changelog of 0.9.1 + 0.9.2; the gallery stays as it is for now
   (owner, 5 Nov: no time); 0.9.3 released on GitHub 5 Nov (PR #19, tag v0.9.3), CurseForge upload
   by the owner (description: log texts and regen line changed); 0.9.4 released on GitHub 6 Nov
   (PR #20, tag v0.9.4), CurseForge upload by the owner on 7 Nov (description: "Fades out of combat"
   line new); 0.9.5 released on GitHub and CurseForge 10 Nov (PR #21, tag v0.9.5; 0.9.4 had 6.1K
   downloads in two days); 0.9.6 merged 10 Nov (PR #22, tag v0.9.6, CurseForge by the owner).
   Reply to the commenters once it is live. SEO from the Full Health Forever session (7 Nov):
   once FHF has its CurseForge page, link both pages to each other (CurseForge descriptions, READMEs,
   GitHub About) and show both flasks side by side; check the GitHub topics (16 of 20 used); a
   feature line "own spells ready in combat straight from the game" only once the duration-object
   test (Psychic Scream) works and FMF uses it. Summary with the full name proposed to the owner; fix bugs, reply to CurseForge comments within 1-2 days. No promotion posts (owner, 17 Oct:
   Blizzard forum, Reddit and notes to other sites dropped; the addon goes its own way).
6. Untested in game: owner's printed list `docs/test-checklist.md`: group log (owner records it
   next); other classes (druid forms, Life Tap, Mana Agate, Evocation)
   when the owner has a character of that level, or from users. Inner Focus tested 17 Oct.
7. 0.8.4 (owner: one release per day until 21 Oct): whole seconds, sound when the potion is
   ready again (option, off), no glow on placeholders. Gallery images 03 (rule row/column) and 10
   show tenths of seconds: re-shoot when convenient. Rest of the HUD polish and the group features
   after launch; they need the group log first. Maybe Wago / WoWInterface mirrors later.
