local M, test, eq, ok = T.M, T.test, T.eq, T.ok

-- helpers ------------------------------------------------------------------
local function bar(ns) return M.upvalue(ns.PositionBar, "bar") end
local function buttons(ns) return M.upvalue(ns.Layout, "buttons") end
-- effective visibility of the potion slot: outer shown and some layer with alpha 1
local function slotVisible(ns, i)
  local b = buttons(ns)[i]
  if not b.outer.shown then return false end
  for _, l in ipairs(b.layers) do
    if l.shown and l.alpha == 1 and b.hp.alpha == 1 then return true, l end
  end
  return false
end
local POT = { [3385] = 2 } -- Lesser Mana Potion, restores up to 360 (max)

-- baseline behaviour ---------------------------------------------------------
test("loads in every language without warnings", function()
  for _, loc in ipairs({ "enUS", "deDE", "ruRU", "esES", "esMX", "frFR", "ptBR", "koKR", "zhCN", "zhTW" }) do
    local ns = M.load(nil, { locale = loc, bags = POT })
    M.tick()
    ns.ToggleOptions(true)
    ns.ToggleLibrary(true)
    eq(#M.warnings(), 0, loc .. " warnings: " .. table.concat(M.warnings(), "|"))
  end
end)

test("potion lights up only when the whole potion fits", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.70; M.tick()   -- deficit 300 < 360
  ok(not slotVisible(ns, 1), "visible at 70%")
  M.state.manaPct = 0.60; M.tick()   -- deficit 400 >= 360
  ok(slotVisible(ns, 1), "hidden at 60%")
end)

test("potion on cooldown is hidden", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2
  M.state.cooldowns[3385] = { 90, 120 }
  M.tick()
  ok(not buttons(ns)[1].outer.shown)
end)

test("old CENTER position is converted to a TOPLEFT pin", function()
  local ns = M.load({ point = { "CENTER", "UIParent", "CENTER", 0, 0 } })
  M.tick()
  eq(ns.db.point[1], "TOPLEFT"); eq(ns.db.point[3], "BOTTOMLEFT")
end)

test("solo/party/raid filter hides icons and bar", function()
  local ns = M.load({ showRaid = false }, { bags = POT })
  M.state.manaPct = 0.2
  M.tick(); ok(buttons(ns)[1].outer.shown, "solo")
  M.state.raid, M.state.group = true, true
  M.tick(); ok(not buttons(ns)[1].outer.shown, "raid"); ok(not bar(ns).shown, "bar in raid")
end)

test("auto bar length does not depend on lit icons, a switched-off group shortens it", function()
  local ns = M.load({ vertical = true, iconSize = 48 }, { bags = POT })
  M.state.manaPct = 1.0; M.tick(); local h1 = bar(ns).h
  M.state.manaPct = 0.2; M.tick()
  ok(slotVisible(ns, 1), "potion not lit")
  eq(bar(ns).h, h1, "a lit icon changed the length")
  ns.db.enabled.rune = false; ns.Layout(true)
  eq(bar(ns).h, h1 - 48 - 6, "a switched-off group still takes room")
end)

-- fixes ------------------------------------------------------------------------
test("mana check failing keeps icons hidden (no wasted potion)", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 1.0
  M.state.powerFails = true
  M.tick()
  ok(not slotVisible(ns, 1), "icon shown at full mana while the mana API fails")
end)

test("mana check recovers after a temporary failure", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2
  M.tick(); ok(slotVisible(ns, 1), "before")
  M.state.powerFails = true; M.tick()
  M.state.powerFails = false; M.tick()
  ok(slotVisible(ns, 1), "did not recover")
end)

test("custom item amount is validated", function()
  local ns = M.load(nil)
  for _, bad in ipairs({ 0, -5, 0/0, 1/0, 1e9 }) do
    ok(not ns.AddCustom(4242, bad, "potion"), "accepted " .. tostring(bad))
  end
  ok(ns.AddCustom(4242, 250.7, "potion"), "valid amount rejected")
  eq(ns.db.custom[1].max, 250)
end)

test("custom entry for a built-in item replaces it instead of doubling", function()
  local ns = M.load(nil)
  ns.AddCustom(3385, 400, "potion")
  local n = 0
  for _, it in ipairs(ns.FullList(1)) do if it.id == 3385 then n = n + 1 end end
  eq(n, 1)
end)

test("equal restore: the sleep potion never wins the tie", function()
  local ns = M.load({ thresholdMode = "avg", disabled = { [12190] = false } },
    { bags = { [13443] = 1, [12190] = 1 } })
  -- put Dreamless Sleep first in the list as a custom item with the same average
  ns.AddCustom(12190, 1200, "potion") -- same as Superior average (900..1500)
  M.state.maxMana = 5000; M.state.manaPct = 0.2; M.tick()
  local _, layer = slotVisible(ns, 1)
  for _, l in ipairs(buttons(ns)[1].layers) do
    if l.shown then ok(l.itemID ~= 12190, "Dreamless Sleep picked") end
  end
end)

test("an error in one group does not blank the others", function()
  local ns = M.load(nil, { bags = { [3385] = 1, [12662] = 1 } })
  M.state.manaPct = 0.1; M.state.maxMana = 5000
  local real = C_Container.GetItemCooldown
  C_Container.GetItemCooldown = function(id) if id == 3385 then error("boom") end return real(id) end
  M.tick()
  ok(buttons(ns)[2].outer.shown, "rune slot blanked by the potion error")
end)

test("bar does not claim full mana when the value cannot be set", function()
  local ns = M.load(nil)
  M.failSetValue = true; M.tick()
  ok(bar(ns).value ~= 1000, "bar shows full mana")
end)

test("mana text comes back after a loading screen", function()
  local ns = M.load(nil)
  local rawformat = string.format
  string.format = function(f, ...)
    if f == "%d / %d" then error("not now") end
    return rawformat(f, ...)
  end
  local okLoop, err = pcall(function() for _ = 1, 30 do M.tick() end end)
  string.format = rawformat
  assert(okLoop, err)
  M.Fire("PLAYER_ENTERING_WORLD")
  M.state.manaPct = 0.5; M.tick()
  eq(bar(ns).text.text, "500 / 1000")
end)

test("old saved data: the macro cleanup flag and the old test mode are dropped", function()
  local ns = M.load({ dbVersion = 6, cleanMacros = true, test = false })
  eq(ns.db.cleanMacros, nil, "macro flag kept")
  eq(ns.db.test, nil, "test key kept")
  eq(ns.db.dbVersion, 8)
end)

-- performance ------------------------------------------------------------------
local function perTick(ns, n)
  for _ = 1, 5 do M.tick() end
  M.calls = {}
  collectgarbage("collect"); collectgarbage("stop")
  local before = collectgarbage("count")
  for _ = 1, n do M.tick() end
  local kb = (collectgarbage("count") - before) / n
  collectgarbage("restart")
  return kb, M.calls
end

test("perf: few item API calls per tick", function()
  local ns = M.load(nil, { bags = { [13444] = 1, [13443] = 1, [3827] = 1, [3385] = 1, [12662] = 1 } })
  M.state.maxMana = 5000; M.state.manaPct = 0.5
  local _, calls = perTick(ns, 10)
  local per = (calls.GetItemCount or 0) / 10
  ok(per <= 16, "GetItemCount per tick: " .. per)
  ok((calls.IsInRaid or 0) / 10 <= 1, "IsInRaid per tick: " .. (calls.IsInRaid or 0) / 10)
  ok((calls.SetMinMaxValues or 0) <= 1, "SetMinMaxValues every tick")
  ok((calls.CreateColorCurve or 0) == 0, "curves rebuilt every tick")
end)

test("perf: little garbage per tick", function()
  local ns = M.load(nil, { bags = { [13444] = 1, [13443] = 1, [3827] = 1, [3385] = 1, [12662] = 1 } })
  M.state.maxMana = 5000; M.state.manaPct = 0.5
  local kb = perTick(ns, 200)
  ok(kb < 1.5, ("%.2f KB garbage per tick"):format(kb))
end)

test("own entry for a known rune keeps its HP safety check", function()
  local ns = M.load(nil, { bags = { [12662] = 1 } })
  ns.AddCustom(12662, 1400, "rune")
  local it
  for _, x in ipairs(ns.FullList(2)) do if x.id == 12662 then it = x end end
  eq(it.hpCost, 1000)
end)

test("tick marks follow a bar thickness change", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.9; M.tick()
  local t = bar(ns).ticks[1][1]
  local before = t.front.h
  ns.db.barThickness = 30; ns.Layout(true); M.tick()
  eq(t.front.h, before + 16, "tick height after thickness 14 -> 30")
end)

test("own amount for a known rune keeps it in the rune slot", function()
  local ns = M.load(nil, { bags = { [12662] = 1 } })
  SlashCmdList.FULLMANAFOREVER("item 12662 1400")
  local inRune, inPotion = false, false
  for _, it in ipairs(ns.FullList(2)) do if it.id == 12662 then inRune = true end end
  for _, it in ipairs(ns.FullList(1)) do if it.id == 12662 then inPotion = true end end
  ok(inRune, "rune left its slot"); ok(not inPotion, "rune moved into the potion slot")
end)

test("known item added to another category stays in its own slot too", function()
  local ns = M.load(nil)
  ns.AddCustom(12662, 1400, "potion") -- explicit (odd) choice of the player
  local inRune = false
  for _, it in ipairs(ns.FullList(2)) do if it.id == 12662 then inRune = true end end
  ok(inRune, "built-in rune entry removed from the rune slot")
end)

test("reset size restores icon and bar sizes, keeps position and other settings", function()
  local ns = M.load({ iconSize = 80, iconGap = 20, barThickness = 30, barLength = 400, fsrScale = 1.5,
    barColor = "teal", point = { "TOPLEFT", "UIParent", "BOTTOMLEFT", 100, 500 } }, { bags = POT })
  M.tick()
  SlashCmdList.FULLMANAFOREVER("reset size")
  M.tick()
  eq(ns.db.iconSize, 44); eq(ns.db.iconGap, 6); eq(ns.db.barThickness, 14); eq(ns.db.barLength, 0)
  eq(ns.db.fsrScale, 1, "text size")
  eq(ns.db.barColor, "teal", "color")
  eq(ns.db.point[4], 100, "x"); eq(ns.db.point[5], 500, "y")
  eq(buttons(ns)[1].outer.w, 44, "icon width")
  eq(bar(ns).h, 14, "bar thickness")
end)

test("options: reset size button resets the sizes", function()
  local ns = M.load({ iconSize = 80 })
  local made, create = {}, CreateFrame
  _G.CreateFrame = function(...) local f = create(...); made[#made + 1] = f; return f end
  ns.ToggleOptions(true)
  _G.CreateFrame = create
  local btn
  for _, f in ipairs(made) do if f.text == ns.L.optResetSize then btn = f end end
  ok(btn, "no reset size button")
  btn.scripts.OnClick(btn)
  eq(ns.db.iconSize, 44)
end)

-- level requirement -------------------------------------------------------------
-- level 16: Lesser Mana Potion (14) is fine, Mana Potion (22) and Greater (31) are not
local LOW = { level = 16, minLevel = { [3385] = 14, [3827] = 22, [6149] = 31 },
  bags = { [3385] = 2, [3827] = 2, [6149] = 2 } }

test("items above your level are never suggested", function()
  local ns = M.load(nil, LOW)
  M.state.manaPct = 0.05; M.tick()  -- low enough for any potion
  local vis, l = slotVisible(ns, 1)
  ok(vis, "no potion shown")
  eq(l.itemID, 3385, "suggested item")
  for _, layer in ipairs(buttons(ns)[1].layers) do
    ok(not (layer.shown and (layer.itemID == 3827 or layer.itemID == 6149)), "too-high potion in a layer")
  end
end)

test("strongest only also skips items above your level", function()
  local ns = M.load({ pickMode = "strongest" }, LOW)
  M.state.manaPct = 0.05; M.tick()
  local vis, l = slotVisible(ns, 1)
  ok(vis, "no potion shown"); eq(l.itemID, 3385)
  local item = ns.GetStatus(1)
  eq(item.id, 3385, "status names a potion you cannot drink")
end)

test("after a level-up the stronger potion comes back", function()
  local ns = M.load(nil, LOW)
  M.state.level = 31
  M.state.manaPct = 0.05; M.tick()
  local _, l = slotVisible(ns, 1)
  eq(l.itemID, 6149)
end)

test("an item the game has not loaded yet is not hidden", function()
  local ns = M.load(nil, { level = 16, uncached = { [3827] = true }, bags = { [3827] = 2 } })
  M.state.manaPct = 0.05; M.tick()
  local vis, l = slotVisible(ns, 1)
  ok(vis, "unknown item hidden"); eq(l.itemID, 3827)
end)

local function diagApis()
  _G.GetPowerRegen = function() return M.secret(3), 1 end
  _G.C_Spell = { GetSpellPowerCost = function() return { { type = 0, cost = 50 } } end,
    GetSpellName = function() return "Heal" end }
  _G.C_UnitAuras = { GetAuraDataByIndex = function(_, i) if i == 1 then return { name = "Innervate", spellId = 29166 } end end,
    GetPlayerAuraBySpellID = function(id) if id == 15271 then return { spellId = 15271 } end end }
end
local function noDiagApis() _G.GetPowerRegen, _G.C_Spell, _G.C_UnitAuras = nil, nil, nil end
local function diagFrame(ns) return M.upvalue(M.upvalue(ns.Probe5SR, "Start"), "frame") end

test("/fmf probe 5sr reports casts, costs and regen, then stops", function()
  local ns = M.load(nil)
  diagApis()
  SlashCmdList.FULLMANAFOREVER("probe 5sr")
  local probe = M.upvalue(ns.Probe5SR, "probe")
  ok(probe.running, "probe not running")
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2050)
  local all = table.concat(M.printed, "\n")
  ok(all:find("spell=2050 Heal", 1, true), "cast not printed")
  ok(all:find("cost=50", 1, true), "cost not printed")
  ok(all:find("base=SECRET casting=1", 1, true), "secret regen not marked")
  ok(all:find("Innervate(29166)", 1, true), "buffs not printed")
  local real = GetTime
  _G.GetTime = function() return 131 end
  local f = diagFrame(ns)
  f.scripts.OnUpdate(f)
  _G.GetTime = real
  ok(not probe.running, "probe did not stop")
  ok(not f.scripts.OnUpdate, "collector still running")
  ok(table.concat(M.printed, "\n"):find("probe done", 1, true), "no done line")
  eq(#M.warnings(), 0, "warnings")
  noDiagApis()
end)

test("/fmf log records into the saved log, never secret contents", function()
  local ns = M.load(nil)
  diagApis()
  SlashCmdList.FULLMANAFOREVER("log on")
  M.Fire("PLAYER_REGEN_DISABLED")
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2050)
  M.Fire("UNIT_AURA", "player")
  local f = diagFrame(ns)
  f.scripts.OnUpdate(f) -- one sample
  SlashCmdList.FULLMANAFOREVER("log off")
  local lines = FullManaForeverLog.lines
  local all = table.concat(lines, "\n")
  ok(all:find("---- session", 1, true), "no session header")
  ok(all:find("combat start", 1, true), "combat not logged")
  ok(all:find("spell=2050 Heal cost: type=0 cost=50", 1, true), "cast not logged")
  ok(all:find("log off", 1, true), "off not logged")
  ok(all:find("byID SpiritTap=yes Innervate=no", 1, true), "buffs by ID not logged")
  ok(all:find("text=ok", 1, true), "secret text test not logged")
  for _, l in ipairs(lines) do
    eq(type(l), "string", "non-string line")
    ok(not issecretvalue(l), "secret stored")
  end
  ok(not FullManaForeverLog.on, "still on")
  noDiagApis()
end)

test("/fmf log keeps running after a reload until switched off", function()
  M.reset()
  local ns = M.load(nil)
  SlashCmdList.FULLMANAFOREVER("log on")
  local saved = FullManaForeverLog
  -- reload: same saved table comes back
  ns = M.load(nil)
  _G.FullManaForeverLog = saved
  M.Fire("PLAYER_LOGIN")
  ok(FullManaForeverLog.on, "log not on after reload")
  ok(diagFrame(ns).scripts.OnUpdate, "collector not running after reload")
  SlashCmdList.FULLMANAFOREVER("log clear")
  eq(#FullManaForeverLog.lines, 0, "not cleared")
end)

-- five-second rule and regen on the mana bar (0.7.0) ----------------------------------
local function regenApis(base, casting)
  _G.GetPowerRegen = function() return base, casting end
  _G.C_Spell = { GetSpellPowerCost = function(id)
    if id == 5019 then return {} end                 -- wand: no cost
    return { { type = 0, cost = 60 } }
  end }
end
local function noRegenApis() _G.GetPowerRegen, _G.C_Spell = nil, nil end

test("a spell that costs mana starts the five-second rule, a wand does not", function()
  local ns = M.load(nil, { bags = POT })
  regenApis(14.75, 0)
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5019)
  eq(ns.FsrLeft(), 0, "wand started the rule")
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "g", 598)
  eq(ns.FsrLeft(), 0, "someone else's cast started the rule")
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 598)
  eq(ns.FsrLeft(), 5, "smite did not start the rule")
  M.tick()
  ok(bar(ns).fsr.shown, "strip hidden during the rule")
  eq(bar(ns).fsr.value, 5)
  eq(bar(ns).regen.text, "0.0/s", "regen during the rule")
  eq(bar(ns).fsrText.text, "5.0", "seconds at the end of the bar")
  ok(bar(ns).fsrText.shown, "seconds hidden")
  local real = GetTime
  _G.GetTime = function() return 106 end
  M.tick()
  _G.GetTime = real
  ok(not bar(ns).fsr.shown, "strip still shown after 5 s")
  ok(not bar(ns).fsrText.shown, "seconds still shown after 5 s")
  eq(bar(ns).regen.text, "14.8/s", "normal regen text")
  noRegenApis()
end)

test("secret regen in combat is shown as text, per second", function()
  local ns = M.load(nil, { bags = POT })
  regenApis(M.secret(14.75), M.secret(0))
  M.tick()
  eq(bar(ns).regen.text, "14.8/s")
  noRegenApis()
end)

test("five-second rule and regen text can be switched off", function()
  local ns = M.load({ fsr = false, regenText = false }, { bags = POT })
  regenApis(14.75, 0)
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 598)
  M.tick()
  ok(not bar(ns).fsr.shown, "strip shown while off")
  ok(not (bar(ns).regen.shown and bar(ns).regenBox.shown), "regen text shown while off")
  noRegenApis()
end)

test("during the rule in combat the secret casting rate is shown", function()
  local ns = M.load(nil, { bags = POT })
  regenApis(M.secret(23.25), M.secret(11.63))
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 598)
  M.tick()
  eq(bar(ns).regen.text, "11.6/s")
  noRegenApis()
end)


test("the regen unit is translated and sits right after the number", function()
  local ns = M.load({ language = "ruRU" }, { bags = POT, locale = "ruRU" })
  regenApis(M.secret(14.75), M.secret(0))
  M.tick()
  eq(bar(ns).regen.text, "14.8/с")
  noRegenApis()
end)

-- mana text like the game's "Status Text" ------------------------------------------------
local function withScale100(fn)
  M.SCALE100 = {}
  _G.CurveConstants = { ScaleTo100 = M.SCALE100 }
  fn()
  _G.CurveConstants, M.SCALE100 = nil, nil
end

test("mana text: number, percentage, both, or switched off", function()
  withScale100(function()
    local ns = M.load({ manaText = "percent" }, { bags = POT })
    M.state.manaPct = 0.89; M.tick()
    eq(bar(ns).text.text, "89%")
    ns.db.manaText = "both"; ns.db.vertical = false; M.tick()
    eq(bar(ns).text.text, "89%   890 / 1000")
    ns.db.vertical = true; M.tick()
    eq(bar(ns).text.text, "89%\n890 / 1000", "column: two lines")
    ns.db.manaTextOn = false; M.tick()
    ok(not bar(ns).manaBox.shown, "mana numbers shown while switched off")
    ns.db.manaTextOn = true; ns.db.manaText = "number"; M.tick()
    ok(bar(ns).manaBox.shown, "mana numbers not back")
    eq(bar(ns).text.text, "890 / 1000")
  end)
end)

test("mana text: without the game's percent curve the number is shown", function()
  local ns = M.load({ manaText = "percent" }, { bags = POT })
  M.state.manaPct = 0.89; M.tick()
  eq(bar(ns).text.text, "890 / 1000")
end)

test("bar markers stay inside the bar; the main one is thicker", function()
  local ns = M.load({ vertical = false }, { bags = { [3385] = 2, [2455] = 2 } })
  M.state.manaPct = 0.95; M.tick()
  local ticks = bar(ns).ticks[1]
  eq(ticks[1].front.h, 14, "main marker sticks out")
  eq(ticks[1].front.w, 3, "main marker not thicker")
  eq(ticks[1].front.alpha, 1)
  ok(ticks[2].front.shown, "second marker missing")
  eq(ticks[2].front.h, 14); eq(ticks[2].front.w, 2)
end)

test("the unlocked frame (test mode) shows the five-second rule without casting", function()
  local ns = M.load({ locked = false }, { bags = POT })
  regenApis(14.75, 0)
  M.tick()
  ok(bar(ns).fsr.shown, "strip hidden in test mode")
  ok(bar(ns).fsrText.shown, "seconds hidden in test mode")
  eq(bar(ns).regen.text, "14.8/s", "regen shows the real rate")
  ns.db.locked, ns.db.fsr = true, true
  M.tick()
  ok(not bar(ns).fsr.shown, "strip still shown after locking")
  ns.db.locked, ns.db.fsr = false, false
  M.tick()
  ok(not bar(ns).fsr.shown, "strip shown although switched off")
  noRegenApis()
end)

test("/fmf scan writes spells, talents and use items with the game's descriptions", function()
  local ns = M.load(nil)
  _G.Enum.SpellBookItemType = { Spell = 1, FutureSpell = 3 }
  _G.C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { name = "Holy", itemIndexOffset = 0, numSpellBookItems = 2 } end,
    GetSpellBookItemInfo = function(i)
      if i == 1 then return { spellID = 14751, name = "Inner Focus" } end
      return { spellID = 14522, name = "Meditation", isPassive = true, itemType = 3 }
    end,
  }
  _G.C_Spell = {
    GetSpellDescription = function(id) return id == 14751 and "Your next spell\ncosts no mana." or "Regen while casting." end,
    GetSpellPowerCost = function() return { { type = 0, cost = 0 } } end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
    GetSpellName = function(id) return "Spell" .. id end,
  }
  _G.GetInventoryItemID = function(_, slot) if slot == 13 then return 23027 end end
  _G.C_Item.GetItemSpell = function(id) if id == 23027 then return "Warmth", 29166 end end
  _G.C_Container.GetContainerNumSlots = function() return 0 end
  _G.GetSpellBaseCooldown = function(id) return id == 14751 and 180000 or 0, 1500 end
  SlashCmdList.FULLMANAFOREVER("scan")
  _G.GetSpellBaseCooldown = nil
  local all = table.concat(FullManaForeverLog.lines, "\n")
  ok(all:find("cd=0+0 base=180", 1, true), "base cooldown missing: " .. all)
  ok(all:find("---- scan", 1, true), "no scan header")
  ok(all:find("spell [Holy] 14751 Inner Focus cost=0 cd=0+0 base=180 : Your next spell | costs no mana.", 1, true), "spell line: " .. all)
  ok(all:find("14522 Meditation (passive) (not learned yet)", 1, true), "passive or future spell not marked")
  ok(all:find("item slot13 23027", 1, true), "use item missing")
  ok(table.concat(M.printed, "\n"):find("scan done: spells=2", 1, true), "no summary")
  ok(all:find("known 29166", 1, true), "spells above level 1 not asked for")
  ok(all:find("talents: old API missing", 1, true), "missing talent API not reported")
  ok(all:find("scan v", 1, true) and all:find("level=", 1, true), "no header")
  _G.C_SpellBook, _G.C_Spell, _G.GetInventoryItemID = nil, nil, nil
end)

test("five-second seconds never cover the mana numbers or the frame label", function()
  local ns = M.load({ vertical = false, fsrScale = 2 }, { bags = POT })
  local b = bar(ns)
  local p = b.fsrBox.points[1]
  eq(p[1], "RIGHT"); eq(p[3], "LEFT", "row: seconds not left of the bar")
  ns.db.vertical = true; ns.Layout(true)
  local label = M.upvalue(ns.ApplyLock, "anchor").label
  ok(label.points[1][5] >= 8 + 28, "column: label not above the seconds: " .. tostring(label.points[1][5]))
  ns.db.fsr = false; ns.Layout(true)
  eq(label.points[1][5], 8, "label offset without the rule")
end)

test("/fmf test is the same switch as unlocking; an old test mode is switched off", function()
  local ns = M.load({ test = true, dbVersion = 5 })
  eq(ns.db.test, nil, "old test mode left on")
  eq(ns.db.locked, true)
  SlashCmdList.FULLMANAFOREVER("test")
  eq(ns.db.locked, false, "/fmf test did not unlock")
  SlashCmdList.FULLMANAFOREVER("test")
  eq(ns.db.locked, true)
end)

test("row: mana numbers outside the bar, on the side away from the icons", function()
  local ns = M.load({ vertical = false, barPosition = "below" }, { bags = POT })
  local p = bar(ns).manaBox.points[1]
  eq(p[1], "TOP"); eq(p[2], bar(ns)); eq(p[3], "BOTTOM", "bar under the icons: numbers not below it")
  ns.db.barPosition = "above"; ns.Layout(true)
  p = bar(ns).manaBox.points[1]
  eq(p[1], "BOTTOM"); eq(p[2], bar(ns)); eq(p[3], "TOP", "bar above the icons: numbers not above it")
  local label = M.upvalue(ns.ApplyLock, "anchor").label
  eq(label.points[1][2], bar(ns).text, "frame label not above the numbers")
end)

-- 0.7.1 review ---------------------------------------------------------------------
test("rune stays hidden when max HP cannot be read (no HP check, no risk)", function()
  local ns = M.load(nil, { bags = { [12662] = 1 } })
  M.state.maxMana, M.state.manaPct = 5000, 0.05 -- the rune (up to 1500) fits
  M.tick()
  ok(slotVisible(ns, 2), "rune hidden although HP is readable and full")
  M.state.maxHP = M.secret(2000)
  M.tick()
  ok(not slotVisible(ns, 2), "rune shown without an HP check")
end)

test("a cooldown waiting for the end of combat counts as not ready", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2
  M.state.cooldowns[3385] = { 0, 0, 0 } -- drunk in combat: enable 0 until combat ends
  M.tick()
  ok(not buttons(ns)[1].outer.shown, "potion shown while its cooldown waits")
  M.state.cooldowns[3385] = nil
  M.tick()
  ok(buttons(ns)[1].outer.shown, "potion not back when ready")
end)

test("regen text turns gold during the rule even with the strip switched off", function()
  local ns = M.load({ fsr = false }, { bags = POT })
  regenApis(14.75, 0)
  M.tick()
  eq(bar(ns).regen.color[1], 0.6, "normal colour")
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 598)
  M.tick()
  eq(bar(ns).regen.text, "0.0/s", "casting rate not shown at once")
  eq(bar(ns).regen.color[1], 1, "casting rate not gold")
  ok(not bar(ns).fsr.shown, "strip shown although switched off")
  noRegenApis()
end)

test("a new install has nothing to migrate", function()
  local ns = M.load(nil)
  eq(ns.db.dbVersion, 8)
  eq(ns.db.cleanMacros, nil, "macro cleanup on a new install")
  eq(ns.db.manaTextOn, true, "mana numbers off on a new install")
end)

test("switching the mana text off hides it even after format failures", function()
  local ns = M.load(nil, { bags = POT })
  _G.UnitPower = function() return {} end -- "%d" cannot format a table
  for _ = 1, 25 do M.tick() end
  ns.db.manaTextOn = false
  bar(ns).text.text = "stale"
  M.tick()
  ok(not bar(ns).manaBox.shown, "stale mana text still shown")
end)

test("old saved data: mana text 'none' becomes the switched-off mana numbers", function()
  local ns = M.load({ dbVersion = 7, manaText = "none" })
  eq(ns.db.manaTextOn, false, "mana numbers back on")
  eq(ns.db.manaText, "number", "'none' left in the list setting")
  ns = M.load({ dbVersion = 7, manaText = "both" })
  eq(ns.db.manaTextOn, true); eq(ns.db.manaText, "both")
end)

test("item ids out of range are rejected", function()
  local ns = M.load(nil)
  for _, id in ipairs({ "inf", "1e300", "0", "1.5" }) do
    ok(not ns.AddCustom(id, 300, "potion"), id .. " accepted")
  end
  ok(ns.AddCustom(4242, 300, "potion"), "valid id rejected")
end)

test("only the player's unit events are heard (no raid-wide handler calls)", function()
  local ns = M.load(nil)
  SlashCmdList.FULLMANAFOREVER("log on")
  local n = 0
  for f in pairs(M.eventFrames) do
    for e in pairs(f.events or {}) do
      if e:find("^UNIT_") and not f.allUnits then
        n = n + 1
        ok(f.unitFilter and f.unitFilter[e] and f.unitFilter[e].player, e .. " registered for every unit")
      end
    end
  end
  ok(n >= 2, "unit events found: " .. n)
  SlashCmdList.FULLMANAFOREVER("log off")
end)

test("/fmf log on with a full log says so instead of claiming it runs", function()
  local ns = M.load(nil)
  FullManaForeverLog.lines = {}
  for i = 1, 6000 do FullManaForeverLog.lines[i] = "x" end
  M.printed = {}
  SlashCmdList.FULLMANAFOREVER("log on")
  ok(not FullManaForeverLog.on, "log on although full")
  eq(#FullManaForeverLog.lines, 6000, "lines added past the limit")
  local all = table.concat(M.printed, "\n")
  ok(all:find("log full", 1, true), "no full message")
  ok(not all:find("log ON", 1, true), "claims the log runs")
  SlashCmdList.FULLMANAFOREVER("scan")
  eq(#FullManaForeverLog.lines, 6000, "scan wrote past the limit")
  ok(table.concat(M.printed, "\n"):find("scan lines dropped", 1, true), "scan does not say lines were dropped")
end)

test("a failing sample does not keep the probe running", function()
  local ns = M.load(nil)
  SlashCmdList.FULLMANAFOREVER("probe 5sr")
  local fsr = ns.FsrLeft
  ns.FsrLeft = function() error("surprise") end
  local f = diagFrame(ns)
  local real = GetTime
  _G.GetTime = function() return 115 end
  f.scripts.OnUpdate(f)
  _G.GetTime = function() return 131 end
  f.scripts.OnUpdate(f)
  _G.GetTime = real
  ns.FsrLeft = fsr
  ok(not M.upvalue(ns.Probe5SR, "probe").running, "probe still running")
  ok(not f.scripts.OnUpdate, "collector still running")
end)

test("a probe started during a log counts its seconds from its own start", function()
  local ns = M.load(nil)
  diagApis()
  SlashCmdList.FULLMANAFOREVER("log on")
  local real = GetTime
  _G.GetTime = function() return 500 end
  SlashCmdList.FULLMANAFOREVER("probe 5sr")
  M.printed = {}
  _G.GetTime = function() return 503 end
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2050)
  _G.GetTime = real
  ok(M.printed[1] and M.printed[1]:find("[^%d%.]3%.0 cast"), "chat stamp: " .. tostring(M.printed[1]))
  SlashCmdList.FULLMANAFOREVER("log off")
  noDiagApis()
end)

test("/fmf log records max health and the potion cooldowns as the game reports them", function()
  local ns = M.load(nil, { bags = POT })
  diagApis()
  M.state.maxHP = M.secret(2000)
  M.state.cooldowns[3385] = { 95, 120, 0 }
  SlashCmdList.FULLMANAFOREVER("log on")
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 438)
  local f = diagFrame(ns)
  f.scripts.OnUpdate(f)
  SlashCmdList.FULLMANAFOREVER("log off")
  local all = table.concat(FullManaForeverLog.lines, "\n")
  ok(all:find("maxHP=SECRET", 1, true), "max health not logged")
  ok(all:find("pots 3385 x2 cd=95+120 en=0 ready=false", 1, true), "potion cooldown not logged: " .. all)
  ok(select(2, all:gsub("pots 3385", "")) >= 2, "potions missing in cast or sample line")
  noDiagApis()
end)

test("/fmf scan trainer lists the trainer spells of TrainerSpells with the game's texts", function()
  local ns = M.load(nil)
  SlashCmdList.FULLMANAFOREVER("scan trainer")
  ok(table.concat(M.printed, "\n"):find("TrainerSpells is not loaded", 1, true), "missing addon not reported")
  _G.TrainerSpellsBuiltin = { PRIEST = { [10] = { [13908] = { cost = 15, rank = 1, race = { "Dwarf", "Human" } },
    [2006] = { cost = 285, rank = 1 } } }, WARRIOR = { [1] = { [100] = { cost = 10 } } } }
  local requested = 0
  _G.C_Spell = { GetSpellName = function(id) return "Spell" .. id end,
    GetSpellDescription = function(id) return "Text " .. id end,
    RequestLoadSpellData = function() requested = requested + 1 end }
  SlashCmdList.FULLMANAFOREVER("scan trainer")
  local all = table.concat(FullManaForeverLog.lines, "\n")
  _G.TrainerSpellsBuiltin, _G.C_Spell = nil, nil
  eq(requested, 2, "texts requested for the mana classes only")
  ok(all:find("trainer PRIEST L10 2006 Spell2006 r1", 1, true), "trainer line: " .. all)
  ok(all:find("13908 Spell13908 r1 race=Dwarf/Human", 1, true), "racial spell not marked")
  ok(not all:find("WARRIOR", 1, true), "class without mana scanned")
end)

test("/fmf scan reads talents through the trait API", function()
  local ns = M.load(nil)
  _G.C_ClassTalents = { GetActiveConfigID = function() return 7 end }
  _G.C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 1 } } end,
    GetTreeNodes = function() return { 11 } end,
    GetNodeInfo = function() return { entryIDs = { 21 }, currentRank = 5, maxRanks = 5 } end,
    GetEntryInfo = function() return { definitionID = 31 } end,
    GetDefinitionInfo = function() return { spellID = 15270 } end,
  }
  _G.C_Spell = { GetSpellName = function() return "Spirit Tap" end,
    GetSpellDescription = function() return "50% while casting" end }
  SlashCmdList.FULLMANAFOREVER("scan")
  local all = table.concat(FullManaForeverLog.lines, "\n")
  _G.C_ClassTalents, _G.C_Traits, _G.C_Spell = nil, nil, nil
  ok(all:find("talent tree=1 node=11 15270 Spirit Tap 5/5 : 50% while casting", 1, true), "talent line: " .. all)
end)

test("/fmf log records group members' casts and the chat test", function()
  local ns = M.load(nil)
  M.state.group = true
  _G.GetNumGroupMembers = function() return 3 end
  _G.UnitName = function(u) return u == "player" and "Me" or ("N" .. u) end
  _G.UnitClass = function(u) if u == "party1" then return "Druid", "DRUID" end return "Class", "PRIEST" end
  SlashCmdList.FULLMANAFOREVER("log on")
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "g", 29166)
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "party2", "g", M.secret(5185))
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate3", "g", 133)
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "party2", "g", 585) -- Smite twice: logged once
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "party2", "g", 585)
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "g", 19742) -- Blessing of Wisdom twice: both
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "g", 19742)
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", M.secret("party1"), "g", 1)
  local sent = {}
  _G.SendChatMessage = function(text, kind, _, to) sent[#sent + 1] = kind .. ":" .. to end
  _G.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(p, text, kind, to) sent[#sent + 1] = "addon:" .. p .. ":" .. tostring(to or kind); return 0 end }
  SlashCmdList.FULLMANAFOREVER("log chat")
  M.Fire("CHAT_MSG_ADDON", "FMF", "test", "WHISPER", "Me")
  SlashCmdList.FULLMANAFOREVER("log off")
  local f = diagFrame(ns)
  f.scripts.OnUpdate(f)
  for g in pairs(M.eventFrames) do
    if g.allUnits then ok(not next(g.events), "group listener still registered after log off") end
  end
  local all = table.concat(FullManaForeverLog.lines, "\n")
  _G.SendChatMessage, _G.C_ChatInfo, _G.UnitName, _G.GetNumGroupMembers = nil, nil, nil, nil
  ok(all:find("group roster members=3 raid=false", 1, true), "roster: " .. all)
  ok(all:find("group member party2 PRIEST level=60 who=Nparty2", 1, true), "roster member")
  ok(all:find("group cast party1 DRUID spell=29166 ? WATCH Innervate combat=false who=Nparty1", 1, true), "innervate: " .. all)
  ok(all:find("group cast party2 PRIEST spell=SECRET", 1, true), "secret group cast")
  ok(not all:find("nameplate3", 1, true), "non-group unit logged")
  local function count(pat) local n = 0; for _ in all:gmatch(pat) do n = n + 1 end return n end
  eq(count("spell=585 "), 1, "a plain spell is logged once per class")
  eq(count("WATCH Wisdom"), 2, "a mana spell is logged every time")
  ok(all:find("group cast unit=SECRET spell=1", 1, true), "secret unit")
  eq(sent[1], "WHISPER:Me"); eq(sent[2], "addon:FMF:Me"); eq(sent[3], "addon:FMF:PARTY")
  ok(all:find("chat test combat=false whisper=sent prefix=true addon=sent 0 group=PARTY sent 0", 1, true), "chat test line")
  ok(all:find("addon msg text=test channel=WHISPER sender=Me", 1, true), "addon message not logged")
end)

-- own mana spells (0.8.0) ------------------------------------------------------------
local SPELL_SLOT = 6
-- a spell book with the given spells (name = "Spell<id>"), cooldowns from cds[id] = { start, dur }
local function spellApis(book, opts)
  opts = opts or {}
  local cds = opts.cds or {}
  _G.Enum.SpellBookSpellBank = { Player = 0 }
  _G.Enum.SpellBookItemType = { Spell = 1, FutureSpell = 3 }
  _G.C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { name = "Class", itemIndexOffset = 0, numSpellBookItems = #book } end,
    GetSpellBookItemInfo = function(i)
      local id = book[i]
      return { spellID = id, name = opts.names and opts.names[id] or ("Spell" .. id),
        itemType = opts.future and opts.future[id] and 3 or 1 }
    end,
  }
  _G.C_Spell = {
    GetSpellName = function(id) return opts.names and opts.names[id] or ("Spell" .. id) end,
    GetSpellTexture = function(id) return "tex" .. id end,
    GetSpellDescription = function(id) return opts.desc and opts.desc[id] or "" end,
    GetSpellCooldown = function(id)
      if opts.secretCd then return M.secret({}) end
      local c = cds[id] or { 0, 0 }
      return { startTime = c[1], duration = c[2], isEnabled = c[3] ~= false }
    end,
    GetSpellPowerCost = function(id)
      if id == 5019 then return {} end -- wand
      return { { type = 0, cost = 50 } }
    end,
  }
  _G.GetSpellBaseCooldown = function(id) return (opts.base and opts.base[id] or 0) * 1000, 1500 end
  return cds
end
local function noSpellApis() _G.C_SpellBook, _G.C_Spell, _G.GetSpellBaseCooldown = nil, nil, nil end
local function spellSlot(ns) return slotVisible(ns, SPELL_SLOT) end

test("Evocation lights up when ready and mana is at or below the setting", function()
  local ns = M.load(nil, { class = "MAGE" })
  spellApis({ 12051 })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.6; M.tick()
  ok(not spellSlot(ns), "shown above 50%")
  M.state.manaPct = 0.4; M.tick()
  local vis, l = spellSlot(ns)
  ok(vis, "hidden at 40%")
  eq(l.icon.texture, "tex12051")
  noSpellApis()
end)

test("own spell on cooldown: exact out of combat, counted from the cast in combat", function()
  local ns = M.load(nil, { class = "MAGE" })
  local cds = spellApis({ 12051 }, { base = { [12051] = 480 } })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2
  cds[12051] = { 99, 1.5 } -- only the global cooldown
  M.tick()
  ok(spellSlot(ns), "global cooldown hides the spell")
  cds[12051] = { 90, 480 }
  M.tick()
  ok(not spellSlot(ns), "spell on cooldown shown out of combat")
  -- in combat the game's cooldown is secret: our own count from the cast decides
  cds[12051] = nil
  M.tick()
  ok(spellSlot(ns), "not ready again after its cooldown")
  spellApis({ 12051 }, { secretCd = true, base = { [12051] = 480 } })
  M.state.combat = true
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 12051)
  M.tick()
  ok(not spellSlot(ns), "shown in combat right after the cast")
  local real = GetTime
  _G.GetTime = function() return 100 + 479 end
  M.tick()
  ok(not spellSlot(ns), "shown before 480 s")
  _G.GetTime = function() return 100 + 481 end
  M.tick()
  _G.GetTime = real
  ok(spellSlot(ns), "not shown after 480 s")
  noSpellApis()
end)

test("Life Tap lights up when its mana fits, with the rune health check", function()
  local ns = M.load(nil, { class = "WARLOCK" })
  spellApis({ 1454 }, { desc = { [1454] = "Converts 300 Health into 300 Mana for you." } })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.8; M.tick() -- deficit 200 < 300
  ok(not spellSlot(ns), "shown although 300 mana do not fit")
  M.state.manaPct = 0.6; M.tick() -- deficit 400
  ok(spellSlot(ns), "hidden although 300 mana fit")
  M.state.healthPct = 0.4; M.tick() -- 300/2000 + 30% = 45% needed
  ok(not spellSlot(ns), "shown with too little health")
  noSpellApis()
end)

test("no mana spells: no slot, no room on the bar; spells are not items", function()
  local ns = M.load(nil, { class = "PRIEST" })
  local before = ns.AutoBarLength()
  spellApis({ 585 })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.1; M.tick()
  ok(not buttons(ns)[SPELL_SLOT].outer.shown, "slot without spells")
  eq(ns.AutoBarLength(), before, "bar room for a missing spell slot")
  spellApis({ 14751 })
  ns.Spells.Rebuild()
  ok(ns.AutoBarLength() > before, "no bar room for Inner Focus")
  ns.AddCustom(4242, 300, "spell")
  for _, c in ipairs(ns.db.custom) do eq(c.group, "potion", "own item went into the spell slot") end
  noSpellApis()
end)

test("unlocked frame previews the own spell; options show its status", function()
  local ns = M.load({ locked = false }, { class = "PRIEST" })
  spellApis({ 14751 }, { names = { [14751] = "Inner Focus" } })
  ns.Spells.Rebuild()
  M.tick()
  local vis, l = spellSlot(ns)
  ok(vis, "no preview"); eq(l.icon.texture, "tex14751")
  ns.db.locked = true
  ns.ToggleOptions(true)
  local found
  for _, r in ipairs(M.upvalue(ns.RefreshOptions, "groupRows")) do
    if ns.GROUPS[r.i].spells then found = r.st.text end
  end
  ok(found and found:find(ns.L.stSpellReady:format("Inner Focus", 50), 1, true), "status: " .. tostring(found))
  noSpellApis()
end)

test("the spell threshold has its own marker on the mana bar", function()
  local ns = M.load({ spellThreshold = 0.3 }, { class = "PRIEST" })
  spellApis({ 1259823 })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.9; M.tick()
  local t = bar(ns).ticks[SPELL_SLOT][1]
  ok(t.front.shown, "no marker for own spells")
  local p = t.front.points[1]
  local len = bar(ns):GetWidth()
  ok(math.abs(p[4] - len * 0.3) < 0.01, "marker not at 30 %: " .. tostring(p[4]) .. " of " .. tostring(len))
  noSpellApis()
end)

test("a global cooldown (cast, wand shot) does not hide the potions", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2
  M.state.cooldowns[3385] = { 99.5, 1.5 } -- every wand shot / cast starts this on items too
  M.tick()
  ok(buttons(ns)[1].outer.shown, "potion hidden by the global cooldown")
  ok(bar(ns).ticks[1][1].front.shown, "potion marker hidden by the global cooldown")
  M.state.cooldowns[3385] = { 90, 120 } -- the potion's own cooldown still hides it
  M.tick()
  ok(not buttons(ns)[1].outer.shown, "potion shown on its own cooldown")
end)

test("a wand shot shows a short sweep on the potion instead of hiding it", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2
  M.state.cooldowns[3385] = { 99, 1.8 }
  M.tick()
  local vis, l = slotVisible(ns, 1)
  ok(vis, "potion hidden during the wand's cooldown")
  ok(l.sweep, "no sweep frame on the icon")
  eq(l.sweep.cdStart, 99, "sweep not started"); eq(l.sweep.cdDur, 1.8)
  ok(l.sweep.hideNumbers, "countdown numbers on a 1.8 s sweep")
  M.calls = {}
  M.tick()
  eq(M.calls.SetCooldown or 0, 0, "sweep set again every tick")
  M.state.cooldowns[3385] = { 99, 4.5 } -- slow bow / two-hander: still not the potion's own
  M.tick()
  ok(slotVisible(ns, 1), "potion hidden by a 4.5 s swing")
  M.state.cooldowns[3385] = nil
  M.tick()
  eq(l.sweep.cdStart, nil, "sweep left on after the wait")
end)

test("nothing is shown while the character is dead or a ghost", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2
  M.tick()
  ok(buttons(ns)[1].outer.shown and bar(ns).shown, "not shown alive")
  M.state.dead = true
  M.tick()
  ok(not buttons(ns)[1].outer.shown, "potion shown while dead")
  ok(not bar(ns).shown, "mana bar shown while dead")
  ns.db.locked = false
  M.tick()
  ok(buttons(ns)[1].outer.shown, "unlocked frame hidden while dead")
  ns.db.locked = true
  M.state.dead = false
  M.tick()
  ok(buttons(ns)[1].outer.shown and bar(ns).shown, "not back after resurrection")
end)

-- 0.8.1 review ---------------------------------------------------------------------
local function at(t, fn) local real = GetTime; _G.GetTime = function() return t end; fn(); _G.GetTime = real end

test("every spell cooldown is read before combat, not only the first ready spell's", function()
  local ns = M.load(nil, { class = "MAGE" })
  local cds = spellApis({ 12051, 1259823 }, { base = { [12051] = 480, [1259823] = 120 } })
  cds[1259823] = { 90, 120 } -- Eureka! on cooldown from before the reload
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2; M.tick() -- out of combat: Evocation ready, shown first
  spellApis({ 12051, 1259823 }, { secretCd = true, base = { [12051] = 480, [1259823] = 120 } })
  M.state.combat = true
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 12051)
  M.tick()
  ok(not spellSlot(ns), "Eureka! shown in combat while still on cooldown")
  at(211, function() M.tick() end)
  ok(spellSlot(ns), "Eureka! not back after its cooldown")
  noSpellApis()
end)

test("with 'only in combat' the cooldowns are still read out of combat", function()
  local ns = M.load({ onlyCombat = true }, { class = "MAGE" })
  local cds = spellApis({ 12051 }, { base = { [12051] = 480 } })
  cds[12051] = { 90, 480 }
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2; M.tick()
  spellApis({ 12051 }, { secretCd = true, base = { [12051] = 480 } })
  M.state.combat = true; M.tick()
  ok(not spellSlot(ns), "Evocation shown in combat although on cooldown")
  noSpellApis()
end)

test("a spell whose cooldown was never read counts as not ready in combat", function()
  local ns = M.load(nil, { class = "MAGE" })
  spellApis({ 12051 }, { secretCd = true })
  ns.Spells.Rebuild()
  M.state.combat = true; M.state.manaPct = 0.2; M.tick()
  ok(not spellSlot(ns), "unknown cooldown shown as ready")
  noSpellApis()
end)

test("Inner Focus: its cooldown starts when the next spell uses the buff", function()
  local ns = M.load(nil, { class = "PRIEST" })
  local cds = spellApis({ 14751 }, { base = { [14751] = 180 } })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2; M.tick()
  ok(spellSlot(ns), "Inner Focus not shown when ready")
  cds[14751] = { 0, 0, false } -- buff up, cooldown waits
  M.tick()
  ok(not spellSlot(ns), "shown while its cooldown waits")
  spellApis({ 14751 }, { secretCd = true, base = { [14751] = 180 } })
  M.state.combat = true
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 14751)
  at(200, function() M.tick() end)
  ok(not spellSlot(ns), "shown before the buff was used")
  at(200, function() M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 5019) end) -- wand: no mana
  at(300, function() M.tick() end)
  ok(not spellSlot(ns), "a wand shot started the cooldown")
  at(300, function() M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2054) end) -- Heal uses it
  at(479, function() M.tick() end)
  ok(not spellSlot(ns), "shown before 180 s after the buff was used")
  at(481, function() M.tick() end)
  ok(spellSlot(ns), "not back 180 s after the buff was used")
  noSpellApis()
end)

test("Life Tap waits for its text: no icon without the health check", function()
  local ns = M.load(nil, { class = "WARLOCK" })
  local desc = {}
  spellApis({ 1454 }, { desc = desc })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.5; M.tick()
  ok(not spellSlot(ns), "Life Tap shown without knowing its mana")
  desc[1454] = "Converts 300 Health into 300 Mana for you."
  M.tick()
  ok(spellSlot(ns), "Life Tap not shown once its text is loaded")
  noSpellApis()
end)

test("a cast of a lower rank starts the cooldown too; spells of later levels do not count", function()
  local ns = M.load(nil, { class = "SHAMAN" })
  spellApis({ 16190, 17359 }, { names = { [16190] = "Tide", [17359] = "Tide" }, base = { [16190] = 300, [17359] = 300 } })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2; M.tick()
  ok(spellSlot(ns), "Mana Tide not shown")
  spellApis({ 16190, 17359 }, { secretCd = true, names = { [16190] = "Tide", [17359] = "Tide" }, base = { [16190] = 300 } })
  M.state.combat = true
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 16190)
  M.tick()
  ok(not spellSlot(ns), "rank 1 cast did not start the cooldown")
  noSpellApis()
  local ns2 = M.load(nil, { class = "DRUID" })
  spellApis({ 29166 }, { future = { [29166] = true } })
  ns2.Spells.Rebuild()
  eq(ns2.Spells.AnyKnown(), false, "a spell of a later level counted as known")
  noSpellApis()
end)

test("options: spell status names the spell that comes back first; no colon after <=", function()
  local ns = M.load(nil, { class = "MAGE" })
  local cds = spellApis({ 12051, 1259823 }, { names = { [12051] = "Evocation", [1259823] = "Eureka" } })
  cds[12051], cds[1259823] = { 90, 480 }, { 90, 120 }
  ns.Spells.Rebuild()
  ns.ToggleOptions(true)
  local st
  for _, r in ipairs(M.upvalue(ns.RefreshOptions, "groupRows")) do
    if ns.GROUPS[r.i].spells then st = r.st.text end
  end
  ok(st and st:find("Eureka", 1, true), "status: " .. tostring(st))
  local found
  for _, w in pairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.label and w.label.text == ns.L.optSpellThr then found = true end
  end
  ok(found, "label of the spell threshold has a colon after <=")
  noSpellApis()
end)

test("a short wand cooldown does not hide a potion's own cooldown", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2
  M.state.cooldowns[3385] = { 90, 120 } -- drunk
  M.tick()
  M.state.cooldowns[3385] = { 99.5, 1.8 } -- next wand shot reported instead
  M.tick()
  ok(not buttons(ns)[1].outer.shown, "potion shown while its own cooldown runs")
  M.state.cooldowns[3385] = nil
  at(211, function() M.tick() end)
  ok(buttons(ns)[1].outer.shown, "potion not back after its cooldown")
  local _, l = slotVisible(ns, 1)
  eq(l.sweep.drawBling, false, "sweep flashes after every shot")
end)

test("perf: little garbage per tick with percent and number text", function()
  local ns = M.load({ manaText = "both" }, { bags = { [13444] = 1, [3827] = 1, [3385] = 1 } })
  M.state.maxMana = 5000; M.state.manaPct = 0.5
  for _ = 1, 5 do M.tick() end
  collectgarbage("collect"); collectgarbage("stop")
  local before = collectgarbage("count")
  for _ = 1, 200 do M.tick() end
  local kb = (collectgarbage("count") - before) / 200
  collectgarbage("restart")
  ok(kb < 1.5, ("%.2f KB garbage per tick"):format(kb))
end)

test("/fmf scan trainer does not break without C_Spell", function()
  local ns = M.load(nil)
  _G.TrainerSpellsBuiltin = { PRIEST = { [1] = { [1243] = { cost = 10 } } } }
  _G.C_Spell = nil
  local okRun = pcall(SlashCmdList.FULLMANAFOREVER, "scan trainer")
  _G.TrainerSpellsBuiltin = nil
  ok(okRun, "scan trainer errored")
  ok(table.concat(FullManaForeverLog.lines, "\n"):find("trainer PRIEST L1 1243", 1, true), "line missing")
end)

test("ptBR names Life Tap correctly", function()
  local ns = M.load(nil, { locale = "ptBR" })
  ok(ns.L.tipSpellThr:find("Tributo de Vida", 1, true), "wrong spell name in ptBR")
end)

test("the spell marker follows the spell the icon shows", function()
  local ns = M.load({ spellThreshold = 0.5 }, { class = "WARLOCK" })
  local cds = spellApis({ 1259823, 1454 }, { desc = { [1454] = "Converts 300 Health into 300 Mana." } })
  cds[1259823] = { 90, 120 } -- Eureka! (first in the list) on cooldown: Life Tap is shown
  ns.Spells.Rebuild()
  M.state.manaPct = 0.9; M.tick()
  local p = bar(ns).ticks[SPELL_SLOT][1].front.points[1]
  local len = bar(ns):GetWidth()
  ok(math.abs(p[4] - len * 0.7) < 0.01, "marker not at Life Tap's 70 %: " .. tostring(p[4] / len))
  noSpellApis()
end)

test("icon shine fades out downwards, no hard half-way line", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2; M.tick()
  for _, b in ipairs(buttons(ns)) do
    for _, l in ipairs(b.layers) do
      eq(l.shine.grad, "VERTICAL")
      eq(l.shine.gradMin.a, 0)       -- bottom edge invisible
      ok(l.shine.gradMax.a <= 0.15, "top too bright")
    end
  end
end)

test("Ley Line reading waits its 2 minutes after a cast in combat, base cooldown unreadable", function()
  local ns = M.load(nil, { class = "PRIEST" })
  spellApis({ 1259705 }) -- GetSpellBaseCooldown reports 0
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2; M.tick() -- read once out of combat: ready
  ok(spellSlot(ns), "ready spell hidden out of combat")
  spellApis({ 1259705 }, { secretCd = true })
  M.state.combat = true
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 1259705)
  local real = GetTime
  _G.GetTime = function() return 100 + 119 end
  M.tick()
  ok(not spellSlot(ns), "shown before 120 s")
  _G.GetTime = function() return 100 + 121 end
  M.tick()
  _G.GetTime = real
  ok(spellSlot(ns), "not shown after 120 s")
  noSpellApis()
end)

test("auto bar length counts only the groups that are switched on, at least 3 icons", function()
  local ns = M.load(nil, { class = "PRIEST" })
  spellApis({ 1259823 }, { base = { [1259823] = 120 } })
  ns.Spells.Rebuild()
  local size, gap = ns.db.iconSize, ns.db.iconGap or 6
  local function len(n) return size * n + gap * (n - 1) end
  eq(ns.AutoBarLength(), len(5), "potion, rune, herb, gear and spell of a priest with Eureka")
  for k in pairs(ns.db.enabled) do ns.db.enabled[k] = false end
  ns.db.enabled.potion = true
  eq(ns.AutoBarLength(), len(3), "only potions: the minimum")
  ns.db.enabled.gem = true
  eq(ns.AutoBarLength(), len(3), "mage gems give a priest no room")
  ns.db.enabled.rune, ns.db.enabled.herb, ns.db.enabled.spell = true, true, true
  eq(ns.AutoBarLength(), len(4), "potion, rune, herb and spell")
  noSpellApis()
end)

test("a wand shot's lock shows on the spell icon too, and never hides it", function()
  local ns = M.load(nil, { class = "PRIEST", bags = POT })
  local cds = spellApis({ 1259823 }, { base = { [1259823] = 120 } })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2
  -- out of combat the game reports the lock on the spell itself: not the spell's cooldown
  cds[1259823] = { 99, 1.8 }
  M.state.cooldowns[3385] = { 99, 1.8 }
  M.tick()
  local vis, l = spellSlot(ns)
  ok(vis, "spell hidden by the wand's lock")
  eq(l.sweep.cdStart, 99, "no sweep on the spell"); eq(l.sweep.cdDur, 1.8)
  -- in combat the spell's cooldown is secret: the items tell
  spellApis({ 1259823 }, { secretCd = true, base = { [1259823] = 120 } })
  M.state.combat = true
  M.state.cooldowns[3385] = { 101, 1.8 }
  M.tick()
  vis, l = spellSlot(ns)
  ok(vis, "spell hidden in combat")
  eq(l.sweep.cdStart, 101, "sweep not following the new shot")
  M.state.cooldowns[3385] = nil
  local real = GetTime
  _G.GetTime = function() return 103 end
  M.tick()
  _G.GetTime = real
  eq(l.sweep.cdStart, nil, "spell sweep left on after the wait")
  noSpellApis()
end)

-- regen text on its own (0.8.2) --------------------------------------------------------
local function regenShown(ns) return bar(ns).regen.shown and bar(ns).regenBox.shown end

test("regen text shows without the mana bar", function()
  local ns = M.load({ showBar = false }, { bags = POT })
  regenApis(14.75, 0)
  M.tick()
  ok(not bar(ns).shown, "bar shown although switched off")
  ok(regenShown(ns), "regen text hidden with the bar")
  eq(bar(ns).regen.text, "14.8/s")
  ns.db.regenText = false; M.tick()
  ok(not bar(ns).regenBox.shown, "regen text shown while off")
  ns.db.regenText = true
  M.state.raid, M.state.group = true, true; ns.db.showRaid = false; M.tick()
  ok(not bar(ns).regenBox.shown, "regen text ignores the solo/party/raid filter")
  noRegenApis()
end)

test("regen text is hidden while dead", function()
  local ns = M.load(nil, { bags = POT })
  regenApis(14.75, 0)
  M.tick(); ok(regenShown(ns), "regen text missing")
  _G.UnitIsDeadOrGhost = function() return true end
  M.tick()
  _G.UnitIsDeadOrGhost = nil
  ok(not bar(ns).regenBox.shown, "regen text shown while dead")
  noRegenApis()
end)

test("regen above normal turns green out of combat; own Evocation also in combat", function()
  local ns = M.load({ fsr = false }, { bags = POT })
  local base = 14.75
  _G.GetPowerRegen = function() return base, 0 end
  _G.C_Spell = { GetSpellPowerCost = function() return {} end }
  M.tick()
  eq(bar(ns).regen.color[1], 0.6, "normal regen not light blue")
  base = 23.25 -- Spirit Tap
  M.state.now = (M.state.now or 100)
  local real = GetTime
  _G.GetTime = function() return 101 end
  M.tick()
  eq(bar(ns).regen.color[2], 1, "raised regen not green"); eq(bar(ns).regen.color[1], 0.45)
  base = 15.0 -- within 10 %: still normal
  _G.GetTime = function() return 102 end
  M.tick()
  eq(bar(ns).regen.color[1], 0.6, "small change turned green")
  -- in combat the value is secret: only an own Evocation counts, for 8 s
  base = M.secret(80)
  M.state.combat = true
  _G.GetTime = function() return 103 end
  M.tick()
  eq(bar(ns).regen.color[1], 0.6, "secret regen guessed as raised")
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 12051)
  _G.GetTime = function() return 104 end
  M.tick()
  eq(bar(ns).regen.color[1], 0.45, "Evocation not green")
  _G.GetTime = function() return 112 end
  M.tick()
  _G.GetTime = real
  eq(bar(ns).regen.color[1], 0.6, "still green after Evocation ended")
  noRegenApis()
end)

test("a new level or other gear learns the normal regen again", function()
  local ns = M.load({ fsr = false }, { bags = POT })
  local base = 14.75
  _G.GetPowerRegen = function() return base, 0 end
  _G.C_Spell = { GetSpellPowerCost = function() return {} end }
  M.tick()
  base = 20
  local real = GetTime
  _G.GetTime = function() return 101 end
  M.tick()
  eq(bar(ns).regen.color[1], 0.45, "raised regen not green")
  M.Fire("PLAYER_LEVEL_UP", 21)
  _G.GetTime = function() return 102 end
  M.tick()
  eq(bar(ns).regen.color[1], 0.6, "regen after a level-up counted as raised")
  base = 30
  _G.GetTime = function() return 103 end
  M.tick()
  eq(bar(ns).regen.color[1], 0.45, "raised regen after the level-up not green")
  M.Fire("PLAYER_EQUIPMENT_CHANGED", 5, true)
  _G.GetTime = function() return 104 end
  M.tick()
  _G.GetTime = real
  eq(bar(ns).regen.color[1], 0.6, "regen after a gear change counted as raised")
  noRegenApis()
end)

test("regen text can be dragged on its own and goes back with /fmf reset", function()
  local ns = M.load({ textFree = true }, { bags = POT })
  regenApis(14.75, 0)
  local box = bar(ns).regenBox
  M.tick()
  ok(not box.mouse, "regen text takes the mouse while locked")
  SlashCmdList.FULLMANAFOREVER("unlock")
  ok(box.mouse, "regen text cannot be dragged while unlocked")
  M.cx, M.cy = 700, 300
  box.scripts.OnDragStop(box)
  M.cx, M.cy = nil, nil
  eq(ns.db.textPoints.regen[1], 700); eq(ns.db.textPoints.regen[2], 300)
  local p = box.points[1]
  eq(p[1], "CENTER"); eq(p[3], "BOTTOMLEFT"); eq(p[4], 700); eq(p[5], 300)
  ns.db.textFree = false; ns.PositionBar()
  ok(box.points[1][2] ~= UIParent, "attached text still at its own place")
  ns.db.textFree = true
  SlashCmdList.FULLMANAFOREVER("reset")
  eq(ns.db.textPoints.regen, nil, "reset kept the regen position")
  ok(box.points[1][2] ~= UIParent, "reset did not put the text back at the bar")
  noRegenApis()
end)

test("a dragged regen text stays in place when its text size changes", function()
  local ns = M.load({ textFree = true, regenScale = 1.5 }, { bags = POT })
  regenApis(14.75, 0)
  local box = bar(ns).regenBox
  SlashCmdList.FULLMANAFOREVER("unlock")
  M.cx, M.cy = 400, 200 -- the frame's own units at 150 %
  box.scripts.OnDragStop(box)
  M.cx, M.cy = nil, nil
  eq(ns.db.textPoints.regen[1], 600); eq(ns.db.textPoints.regen[2], 300)
  -- the same screen spot at any size: offset x scale stays 600 / 300
  for _, scale in ipairs({ 1, 1.5, 2 }) do
    ns.db.regenScale = scale; ns.PositionBar()
    local p = box.points[1]
    eq(p[4] * box:GetScale(), 600, "x moved at scale " .. scale)
    eq(p[5] * box:GetScale(), 300, "y moved at scale " .. scale)
  end
  noRegenApis()
end)

test("mana numbers and the rule's seconds also show without the mana bar", function()
  local ns = M.load({ showBar = false }, { bags = POT })
  regenApis(14.75, 0)
  M.state.manaPct = 0.89; M.tick()
  ok(bar(ns).manaBox.shown, "mana numbers hidden with the bar")
  eq(bar(ns).text.text, "890 / 1000")
  ok(not bar(ns).fsrBox.shown, "seconds shown without a cast")
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 598)
  M.tick()
  ok(bar(ns).fsrBox.shown and bar(ns).fsrText.shown, "rule's seconds hidden with the bar")
  ok(not bar(ns).fsr.shown, "strip shown without the bar")
  ns.db.manaTextOn = false; M.tick()
  ok(not bar(ns).manaBox.shown, "mana numbers shown although switched off")
  noRegenApis()
end)

test("each text can be dragged on its own; the others stay with the bar", function()
  local ns = M.load({ textFree = true, vertical = true, fsrScale = 2 }, { bags = POT })
  regenApis(14.75, 0)
  local b = bar(ns)
  SlashCmdList.FULLMANAFOREVER("unlock")
  ok(b.manaBox.mouse and b.fsrBox.mouse and b.regenBox.mouse, "a text cannot be dragged")
  -- the mana numbers leave: the regen moves up under the bar instead of following them
  M.cx, M.cy = 100, 50
  b.manaBox.scripts.OnDragStop(b.manaBox)
  eq(ns.db.textPoints.mana[1], 100)
  eq(b.manaBox.points[1][1], "CENTER"); eq(b.manaBox.points[1][2], UIParent)
  eq(b.regenBox.points[1][2], b, "regen follows the dragged mana numbers")
  -- the seconds at 200 %: saved in screen units
  M.cx, M.cy = 30, 40
  b.fsrBox.scripts.OnDragStop(b.fsrBox)
  M.cx, M.cy = nil, nil
  eq(ns.db.textPoints.fsr[1], 60); eq(ns.db.textPoints.fsr[2], 80)
  eq(b.fsrBox.points[1][4], 30); eq(b.fsrBox.points[1][5], 40)
  SlashCmdList.FULLMANAFOREVER("reset")
  eq(next(ns.db.textPoints), nil, "reset kept a text position")
  ok(b.manaBox.points[1][2] == b and b.fsrBox.points[1][2] == b, "texts not back at the bar")
  SlashCmdList.FULLMANAFOREVER("lock")
  ok(not (b.manaBox.mouse or b.fsrBox.mouse or b.regenBox.mouse), "a text takes the mouse while locked")
  noRegenApis()
end)

test("row above the icons: the frame label leaves dragged mana numbers alone", function()
  local ns = M.load({ textFree = true, barPosition = "above" }, { bags = POT })
  local label = M.upvalue(ns.ApplyLock, "anchor").label
  eq(label.points[1][2], bar(ns).text)
  ns.db.textPoints.mana = { 300, 300 }; ns.PositionBar()
  eq(label.points[1][2], bar(ns), "label follows the dragged mana numbers")
end)
