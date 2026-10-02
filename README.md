# Full Mana Forever

World of Warcraft: Forever addon for mana users. Shows a mana potion or rune **only when
it is off cooldown AND your mana deficit is at least its maximum restore**, so no mana
is wasted.

Your current mana is a secret value in Forever. The addon never reads it: it hands a
step curve to `UnitPowerPercent`, and the game applies the resulting (secret) alpha to
the icon. Item cooldowns and max mana are readable and handled normally.

## Supported (v0.6)
- Mana potions (shared potion cooldown): Major, Major Rejuvenation, Superior, Greater,
  Mana, Lesser, Minor. The best one you carry is shown.
- Demonic Rune / Dark Rune (own cooldown), shown only with enough health.

- Mana gems (mage), other consumables (Night Dragon's Breath, battleground draughts), use effects of
  equipped gear (Warmth of Forgiveness, Recombobulators, Robe of the Archmage).

Values checked against the Wowhead Forever database (build 1.60.1), see `Data.lua`.

## Options
- **Drinking**: *No waste* shows the strongest potion that fits completely into your missing mana;
  *More per fight* uses the average restore (earlier, sometimes a small overflow); *Strongest only*.
- **Show**: solo / in a party / in a raid (any combination), optionally only in combat.
- **Mana bar with markers**: your mana (drawn by the game) with a mark where each icon appears; under, above,
  left or right of the icons, in a row or a column; color, thickness and length are adjustable.

## Commands
| Command | Does |
|---|---|
| `/fmf` | open the settings window (also in Settings > AddOns and the addon compartment) |
| `/fmf items` | item list window (enable/disable items, add your own) |
| `/fmf hold` | hold potions (stop suggesting them) / release again |
| `/fmf unlock` / `/fmf lock` | move the icons |
| `/fmf test` | show icons whenever ready, ignoring mana (pipeline check) |
| `/fmf item <id> <amount>` | add your own item to the potion group (testing) |
| `/fmf item clear` | remove custom items |
| `/fmf probe` | print API status (please attach to bug reports) |
| `/fmf debug` | debug messages |
| `/fmf scale` | switch curve scale 0..1 / 0..100 (only if the icon never reacts) |
| `/fmf reset` | reset position |

The addon does not drink for you. Put your potions on the action bar and press them when the icon lights up.

## Install
Copy the `FullManaForever` folder to `_classic_beta_\Interface\AddOns`.

License: MIT
