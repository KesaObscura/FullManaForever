local _, ns = ...

-- Each group is one icon slot. Groups with a shared cooldown (potions, runes, gems) can
-- stack several items in the slot: the strongest one that fits the missing mana is shown.
-- Other groups show the first item in this order that you carry (or have equipped and ready).
-- min/max = mana restored (threshold: deficit >= max, or >= average in "More per fight")
-- hpCost = maximum health the item costs (runes); icon also needs enough HP
-- defaultOff = not suggested until the player ticks it in the item list
-- pvp    = only usable in battlegrounds
-- class  = only this class can use it (group or item); hidden for everyone else
-- Every value below was checked against the Wowhead Forever database (build 1.60.1).
ns.GROUPS = {
  {
    key = "potion", -- shared potion cooldown (2 min)
    items = {
      { id = 13444, min = 1350, max = 2250 },  -- Major Mana Potion (1350-2250)
      { id = 18253, min = 1440, max = 1760 },  -- Major Rejuvenation Potion (1440-1760 mana + health)
      { id = 13443, min = 900, max = 1500 },  -- Superior Mana Potion (900-1500)
      { id = 12190, min = 1200, max = 1200, defaultOff = true, sleep = true }, -- Dreamless Sleep Potion (1200 over 12 s asleep)
      { id = 6149, min = 700, max = 900 },   -- Greater Mana Potion (700-900)
      { id = 3827, min = 455, max = 585 },   -- Mana Potion (455-585)
      { id = 3385, min = 280, max = 360 },   -- Lesser Mana Potion (280-360)
      { id = 2455, min = 140, max = 180 },   -- Minor Mana Potion (140-180)
      { id = 2456, min = 90, max = 150 },   -- Minor Rejuvenation Potion (90-150 mana + health)
    },
  },
  {
    key = "rune", -- own cooldown (2 min)
    items = {
      { id = 12662, min = 900, max = 1500, hpCost = 1000 },  -- Demonic Rune (900-1500, costs 600-1000 HP)
      { id = 20520, min = 900, max = 1500, hpCost = 1000 },  -- Dark Rune
    },
  },
  {
    key = "gem", -- conjured mage gems (2 min), soulbound to the mage
    class = "MAGE",
    items = {
      { id = 8008, min = 1000, max = 1200 },   -- Mana Ruby (1000-1200)
      { id = 8007, min = 775, max = 925 },    -- Mana Citrine (775-925)
      { id = 5513, min = 550, max = 650 },    -- Mana Jade (550-650)
      { id = 5514, min = 375, max = 425 },    -- Mana Agate (375-425)
    },
  },
  {
    key = "herb", -- other consumables with mana; items have different cooldowns
    preferReady = true,
    items = {
      { id = 17351, min = 980, max = 1260, pvp = true }, -- Major Mana Draught (980-1260, battlegrounds, 5 min)
      { id = 17352, min = 560, max = 720,  pvp = true }, -- Superior Mana Draught (560-720, battlegrounds, 5 min)
      { id = 11952, min = 394, max = 456 },   -- Night Dragon's Breath (394-456 mana + health)
    },
  },
  {
    key = "gear", -- use effects of equipped items, each with its own cooldown
    equipped = true,
    items = {
      { id = 14152, min = 375, max = 625, class = "MAGE" }, -- Robe of the Archmage (mage chest, 375-625, 5 min)
      { id = 23027, min = 500, max = 500 },   -- Warmth of Forgiveness (trinket, 500, 3 min)
      { id = 18637, min = 228, max = 380 },   -- Major Recombobulator (trinket, 228-380 mana + health, 5 min)
      { id = 4381, min = 96, max = 160 },   -- Minor Recombobulator (trinket, 96-160 mana + health, 5 min)
    },
  },
  {
    key = "spell", -- own spells that give or save mana (ns.SPELLS), each with its own cooldown
    spells = true,
    items = {},
  },
}

-- Own spells, first ready one wins (texts and cooldowns from /fmf scan in Forever).
-- id: any rank; the player's own rank is found by name in the spell book.
-- cd: seconds, used in combat where the game's cooldown is secret (the game's base cooldown
-- is preferred when it can be read). Without "fit" the icon lights up at or below the
-- "Spells at mana" setting; "fit": the mana it gives (from its description) must fit into
-- the missing mana and it costs that much health (Life Tap). afterUse: the cooldown starts
-- only when the buff is used up by the next spell.
ns.SPELLS = {
  { key = "evocation",  id = 12051,   class = "MAGE",    cd = 480 }, -- +1500 % regen for 8 s
  { key = "innervate",  id = 29166,   class = "DRUID",   cd = 360 }, -- +400 % regen for 20 s
  { key = "manatide",   id = 16190,   class = "SHAMAN",  cd = 300 }, -- talent, group mana
  { key = "leyline",    id = 1259705, cd = 120 },                  -- Skyborne: +100 % regen
  { key = "innerfocus", id = 14751,   class = "PRIEST",  cd = 180, afterUse = true }, -- next spell free;
                                                  -- its cooldown starts when the buff is used
  { key = "eureka",     id = 1259823, cd = 120 },                  -- Gnome: 3 spells 10 % cheaper
  { key = "lifetap",    id = 1454,    class = "WARLOCK", fit = true }, -- health to mana
}
