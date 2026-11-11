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
- **Texts for players say what a thing does and when, never how it is done** (owner, 11 Nov):
  tooltips, changelog, CurseForge and README carry no word about the game calls or tricks behind
  a feature.
- **No technical notes in this repository** (owner, 11 Nov): what was found out about the game,
  test results, the owner's decisions and the roadmap live in the owner's private repository
  (`FMF-CLAUDE.md`, `FMF-NOTES.md`, `FMF-INTERNALS.md` there). **Before any work, attach that
  repository (ask the owner if it is not in the session) and read `FMF-CLAUDE.md`**; write new
  findings and decisions there, never here. Code comments say what the code does, briefly.
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
  categories, GitHub About/topics and the gallery order are in the private notes.
- GitHub release: the owner creates the tag `vX.Y.Z` (this session cannot push tags); not a
  pre-release; the same changelog text and zip `FullManaForever-X.Y.Z.zip` (no hash). Title
  "Full Mana Forever X.Y.Z – WoW Forever mana addon"; body = two-line pitch, install line
  ([CurseForge](https://www.curseforge.com/wow/addons/full-mana-forever) app or unzip into Interface/AddOns), the changelog, bug-report link.
- Gallery: 1280x720 PNGs by `tools/gallery.py` from the owner's in-game screenshots (English
  addon texts); finished images in `docs/gallery/`. When a change alters what an image shows,
  ask the owner for screenshots. Source screenshots never go into the repo (names, chat).
