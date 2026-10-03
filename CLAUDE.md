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
