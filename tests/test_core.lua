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
  eq(ns.acct.custom[1].max, 250)
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
  eq(ns.acct.dbVersion, 10)
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
  eq(t.front.h, before + 14, "tick height after thickness 16 -> 30")
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
  eq(ns.db.iconSize, 48); eq(ns.db.iconGap, 6); eq(ns.db.barThickness, 16); eq(ns.db.barLength, 0)
  eq(ns.db.fsrScale, 1, "text size")
  eq(ns.db.barColor, "teal", "color")
  eq(ns.db.point[4], 100, "x"); eq(ns.db.point[5], 500, "y")
  eq(buttons(ns)[1].outer.w, 48, "icon width")
  eq(bar(ns).h, 16, "bar thickness")
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
  eq(ns.db.iconSize, 48)
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
  eq(bar(ns).fsrText.text, "5", "whole seconds at the end of the bar")
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
  eq(ticks[1].front.h, 16, "main marker sticks out")
  eq(ticks[1].front.w, 3, "main marker not thicker")
  eq(ticks[1].front.alpha, 1)
  ok(ticks[2].front.shown, "second marker missing")
  eq(ticks[2].front.h, 16); eq(ticks[2].front.w, 2)
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

test("/fmf test is the same as /fmf unlock (no toggle); an old test mode is switched off", function()
  local ns = M.load({ test = true, dbVersion = 5 })
  eq(ns.db.test, nil, "old test mode left on")
  eq(ns.db.locked, true)
  SlashCmdList.FULLMANAFOREVER("test")
  eq(ns.db.locked, false, "/fmf test did not unlock")
  SlashCmdList.FULLMANAFOREVER("test")
  eq(ns.db.locked, false, "a second /fmf test locked the frame again")
  SlashCmdList.FULLMANAFOREVER("lock")
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
  eq(ns.acct.dbVersion, 10)
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
    GetSpellLevelLearned = function(id) return opts.learned and opts.learned[id] or 0 end,
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

test("Evocation lights up when ready and mana is at or below its own threshold (35 %)", function()
  local ns = M.load(nil, { class = "MAGE" })
  spellApis({ 12051 })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.4; M.tick()
  ok(not spellSlot(ns), "shown above 35%")
  M.state.manaPct = 0.3; M.tick()
  local vis, l = spellSlot(ns)
  ok(vis, "hidden at 30%")
  eq(l.icon.texture, "tex12051")
  noSpellApis()
end)

test("own spell on cooldown: exact out of combat, counted from the cast in combat", function()
  local ns = M.load(nil, { class = "MAGE" })
  ns.db.cdShow = 0 -- the icon is not shown before it is ready (counting checked here)
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
  for _, c in ipairs(ns.acct.custom) do eq(c.group, "potion", "own item went into the spell slot") end
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
  ok(found and found:find(ns.L.stSpellReady:format("Inner Focus", 75), 1, true), "status: " .. tostring(found))
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
  ns.db.cdShow = 0 -- the icon is not shown before it is ready (counting checked here)
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
  ok(not spellSlot(ns), "the missing text is asked for at most once a second")
  at(101, function() M.tick() end)
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

test("options: spell status names the spell that comes back first", function()
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

test("ptBR names Life Tap correctly", function()
  local ns = M.load(nil, { locale = "ptBR" })
  ok(ns.L.tipSpellFit:find("Tributo de Vida", 1, true), "wrong spell name in ptBR")
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
  ns.db.cdShow = 0 -- the icon is not shown before it is ready (counting checked here)
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

test("regen lowered by Resurrection Sickness is not learned as normal (0.8.9)", function()
  local ns = M.load({ fsr = false }, { bags = POT })
  local base, neg, sick = 3.9, -36, false   -- in game: Spirit 38 = 48 + 26 - 36; aura not seen
  _G.GetPowerRegen = function() return base, 0 end
  _G.C_Spell = { GetSpellPowerCost = function() return {} end }
  _G.UnitStat = function(_, i) return 48 + 26 + neg, 48 + 26 + neg, 26, neg end
  _G.C_UnitAuras = { GetPlayerAuraBySpellID = function(id) if sick and id == 15007 then return { spellId = 15007 } end end }
  local real = GetTime
  _G.GetTime = function() return 101 end
  M.tick()                                   -- under the debuff: nothing learned, not green
  eq(bar(ns).regen.color[1], 1, "lowered regen not red"); eq(bar(ns).regen.color[2], 0.35)
  ok(bar(ns).regenDown.shown, "no down arrow under the debuff")
  ok(not bar(ns).regenUp.shown, "up arrow under the debuff")
  base, neg, sick = 15.5, 0, false          -- debuff gone: this is normal regen
  _G.GetTime = function() return 102 end
  M.tick()
  eq(bar(ns).regen.color[1], 0.6, "normal regen after the debuff counted as raised")
  ok(not bar(ns).regenUp.shown, "arrow after the debuff")
  ok(not bar(ns).regenDown.shown, "down arrow after the debuff")
  base = 25                                  -- a real boost still turns green
  _G.GetTime = function() return 103 end
  M.tick()
  eq(bar(ns).regen.color[1], 0.45, "raised regen not green")
  -- the aura alone (stats not lowered) also keeps the value out
  M.Fire("PLAYER_LEVEL_UP", 22)
  base, sick = 3.9, true
  _G.GetTime = function() return 104 end
  M.tick()
  base, sick = 15.5, false
  _G.GetTime = function() return 105 end
  M.tick()
  eq(bar(ns).regen.color[1], 0.6, "aura: normal regen counted as raised")
  -- gear with a few points less Spirit is normal: its regen is learned
  M.Fire("PLAYER_EQUIPMENT_CHANGED", 5, true)
  base, neg = 13, -3
  _G.GetTime = function() return 106 end
  M.tick()
  base, neg = 15.5, 0
  _G.GetTime = function() return 107 end
  M.tick()
  _G.GetTime = real
  eq(bar(ns).regen.color[1], 0.45, "regen with gear minus Spirit not learned as normal")
  _G.UnitStat, _G.C_UnitAuras = nil, nil
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


-- 0.8.3 ------------------------------------------------------------------------------
test("/fmf hold keeps the potion switch, shows the potion grey with HOLD, ends after the next fight", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2; M.tick()
  local b = buttons(ns)[1]
  ok(slotVisible(ns, 1), "potion not lit")
  SlashCmdList.FULLMANAFOREVER("hold")
  eq(ns.db.enabled.potion, true, "hold switched the potion group off")
  M.tick()
  ok(slotVisible(ns, 1), "held potion hidden instead of grey")
  ok(b.layers[1].icon.desaturated, "held potion not grey")
  local ht = b.layers[1].holdText
  ok(ht.shown, "no HOLD text"); eq(ht.text, ns.L.holdLabel)
  -- the word lives inside the layer, so the mana band (layer alpha) hides it with the icon
  ok(ht.parent.parent == b.layers[1], "HOLD text outside the potion layer")
  -- a long word (RESERVA) on a small icon shrinks to fit
  ht.textScale = nil; b.layers[1].holdFitW = nil; ht:SetText("RESERVA"); b.outer:SetSize(30, 30)
  M.tick()
  ok(ht.textScale and ht.textScale < 1 and 42 * ht.textScale <= 27.01, "word does not fit: " .. tostring(ht.textScale))
  ok(not b.layers[1].glow.shown, "held potion still glows")
  -- the unlocked frame shows the potion as it looks when lit, without HOLD
  ns.db.locked = false; M.tick()
  ok(not ht.shown and not b.layers[1].icon.desaturated, "HOLD on the unlocked frame")
  ns.db.locked = true; M.tick()
  ok(ht.shown, "HOLD not back after locking")
  -- out of combat nothing ends it; the end of a fight does
  M.Fire("PLAYER_REGEN_ENABLED"); eq(ns.IsHeld(), true, "hold ended without a fight")
  M.state.combat = true; M.Fire("PLAYER_REGEN_DISABLED")
  M.state.combat = false; M.Fire("PLAYER_REGEN_ENABLED")
  eq(ns.IsHeld(), false, "hold still on after the fight")
  M.tick()
  ok(not b.layers[1].icon.desaturated, "potion stays grey"); ok(not ht.shown, "HOLD text stays")
  ok(b.layers[1].glow.shown, "glow not back")
  -- a second /fmf hold ends it early
  SlashCmdList.FULLMANAFOREVER("hold"); eq(ns.IsHeld(), true)
  SlashCmdList.FULLMANAFOREVER("hold"); eq(ns.IsHeld(), false)
end)

test("hold started during a fight ends when that fight ends", function()
  local ns = M.load(nil, { bags = POT })
  M.state.combat = true
  SlashCmdList.FULLMANAFOREVER("hold")
  M.state.combat = false; M.Fire("PLAYER_REGEN_ENABLED")
  eq(ns.IsHeld(), false)
end)

test("login: a short tip only the first time, the version line only when it changes", function()
  local function logins(db)
    local ns = M.load(db)
    return ns, table.concat(M.printed, "\n")
  end
  local ns, out = logins(nil)
  ok(out:find("unlock", 1, true), "no first-run tip: " .. out)
  eq(ns.acct.seenVersion, ns.VERSION)
  ns, out = logins({ seenVersion = ns.VERSION })
  ok(not out:find(ns.VERSION, 1, true) and not out:find("unlock", 1, true), "login message on every login: " .. out)
  ns, out = logins({ seenVersion = "0.0.1" })
  ok(out:find(ns.VERSION, 1, true), "no line after an update: " .. out)
  ns, out = logins({ dbVersion = 8 })
  ok(out:find(ns.VERSION, 1, true) and not out:find("unlock", 1, true), "update from 0.8.2 shows the first-run tip: " .. out)
end)


test("0.8.4: whole seconds; a placeholder does not glow; optional sound when the potion is ready again", function()
  local ns = M.load(nil, { bags = { [3385] = 2 } })
  -- seconds: 4.2 left shows 5, 0.4 left shows 1
  regenApis(14.75, 0)
  local real = GetTime
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 598)
  _G.GetTime = function() return real() + 0.8 end; M.tick()
  eq(bar(ns).fsrText.text, "5")
  _G.GetTime = function() return real() + 4.6 end; M.tick()
  eq(bar(ns).fsrText.text, "1")
  ns.db.fsrWhole = false; M.tick()
  eq(bar(ns).fsrText.text, "0.4", "tenths when whole seconds are off")
  ns.db.fsrWhole = true
  _G.GetTime = real
  -- unlocked frame: a group with nothing in the bags shows a grey placeholder without glow
  ns.db.locked = false; M.tick()
  local b = buttons(ns)
  ok(b[1].layers[1].glow.shown, "potion in the bags does not glow in the preview")
  ok(not b[2].layers[1].glow.shown, "placeholder rune glows")
  ns.db.locked = true; M.tick()
  -- sound: off by default; on, it plays once when the potion cooldown is over
  local t0 = real()
  local function at(sec) _G.GetTime = function() return t0 + sec end; M.tick() end
  M.state.cooldowns[3385] = { t0, 120 }
  at(1); at(121)
  eq(#M.sounds, 0, "sound although switched off")
  ns.db.potionSound = true
  M.state.cooldowns[3385] = { t0 + 200, 120 }
  at(201); eq(#M.sounds, 0, "sound while on cooldown")
  at(321); eq(#M.sounds, 1, "no sound when the potion is ready again")
  ok(tostring(M.sounds[1]):find("Sounds\\drop%-and%-bell%.ogg"), "not the addon's own sound: " .. tostring(M.sounds[1]))
  at(322); eq(#M.sounds, 1, "sound repeats")
  -- a wand shot's short lock is no potion cooldown
  M.state.cooldowns[3385] = { t0 + 400, 1.8 }
  at(400.5); at(403)
  eq(#M.sounds, 1, "sound after a wand shot")
  -- another of the three sounds
  ns.db.potionSoundKind = "crystal"
  ns.PlayPotionSound()
  ok(tostring(M.sounds[#M.sounds]):find("crystal%-rise%.ogg"), "picked sound not played")
  _G.GetTime = real
end)


test("regen above normal also shows an up arrow (not colour alone)", function()
  local ns = M.load(nil)
  regenApis(15.5, 0); M.tick()
  ok(not bar(ns).regenUp.shown, "arrow at normal regen")
  regenApis(36.3, 20.8)
  _G.GetTime = (function(r) return function() return r() + 1 end end)(GetTime); M.tick()
  ok(bar(ns).regenUp.shown, "no arrow above normal")
end)

-- 0.8.6: fixes from the code review

test("Inner Focus still waits for the next spell after the spell book changes", function()
  local ns = M.load(nil, { class = "PRIEST" })
  local cds = spellApis({ 14751 }, { base = { [14751] = 180 } })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2; M.tick()
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 14751)
  cds[14751] = { 0, 0, false } -- buff up, cooldown waits
  M.tick()
  M.Fire("SPELLS_CHANGED") -- a new rank or talent out of combat
  spellApis({ 14751 }, { secretCd = true, base = { [14751] = 180 } })
  M.state.combat = true
  at(200, function() M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 2050) end) -- the next spell
  at(390, function() M.tick() end)
  ok(spellSlot(ns), "Inner Focus not back 180 s after the buff was used")
  M.state.combat = false
  noSpellApis()
end)

test("auto bar length follows the spell book (first mana spell learned)", function()
  local ns = M.load({ vertical = true, iconSize = 48, iconGap = 6 }, { class = "MAGE" })
  spellApis({})
  ns.Spells.Rebuild()
  M.tick()
  local bar = M.upvalue(ns.PositionBar, "bar")
  local h1 = bar.h
  spellApis({ 12051 })
  M.Fire("SPELLS_CHANGED")
  eq(bar.h, h1 + 48 + 6, "bar length after learning Evocation")
  noSpellApis()
end)

test("own spells: cooldowns are read once per tick, a missing Life Tap text once a second", function()
  local ns = M.load(nil, { class = "MAGE" })
  spellApis({ 12051 })
  local reads, real = 0, C_Spell.GetSpellCooldown
  C_Spell.GetSpellCooldown = function(id) reads = reads + 1; return real(id) end
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2
  M.tick(); reads = 0
  ns.ToggleOptions(true) -- the settings ask for the spells too
  at(101, function() M.tick() end)
  eq(reads, 1, "cooldown read again in the same tick")
  noSpellApis()
end)

test("battleground check once per tick", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2
  M.tick(); M.calls = {}
  M.tick()
  ok((M.calls.IsInInstance or 0) <= 1, "IsInInstance per tick: " .. tostring(M.calls.IsInInstance))
end)

test("a damaged saved position or text place does not break the login", function()
  local saved = { point = { "CENTER", "UIParent" }, textFree = true, textPoints = { mana = "x", fsr = { 1 } } }
  local ns = M.load(saved)
  local p = ns.db.point
  ok(type(p[4]) == "number" and type(p[5]) == "number", "position not repaired")
  local a = _G.FullManaForeverAnchor.points[1]
  ok(a and type(a[4]) == "number", "frame without a valid point")
  ok(ns.Layout and true, "login stopped")
end)

test("an empty mana band (lower edge = upper edge) is never shown", function()
  local ns = M.load(nil)
  -- the local function, reached through the upvalues of the addon's functions
  local seenFn, Band = {}, nil
  local function find(f)
    if Band or seenFn[f] then return end
    seenFn[f] = true
    local i = 1
    while true do
      local n, v = debug.getupvalue(f, i)
      if not n then return end
      if n == "BandCurve" then Band = v return end
      if type(v) == "function" then find(v) end
      i = i + 1
    end
  end
  for _, f in pairs(ns) do if type(f) == "function" then find(f) end end
  for _, fr in ipairs(M.all) do
    for _, sc in pairs(fr.scripts or {}) do if type(sc) == "function" then find(sc) end end
  end
  ok(Band, "BandCurve not found")
  local c = Band(0.5, 0.5)
  local xs = {}
  for _, pt in ipairs(M.upvalue(c.AddPoint, "pts")) do
    ok(not xs[pt[1]], "two curve points at " .. pt[1]); xs[pt[1]] = true
  end
  for _, x in ipairs({ 0, 0.3, 0.5, 0.50005, 0.7, 1 }) do
    eq(c:Evaluate(x).a, 0, "shown at " .. x)
  end
end)

test("HOLD follows a language change", function()
  local ns = M.load(nil, { bags = POT })
  M.state.manaPct = 0.2; M.tick()
  SlashCmdList.FULLMANAFOREVER("hold")
  M.tick()
  local ht = buttons(ns)[1].layers[1].holdText
  eq(ht.text, "HOLD")
  ns.acct.language = "deDE"; ns.SetLanguage("deDE")
  M.tick()
  eq(ht.text, "HALT", "HOLD still in the old language")
end)

-- 0.8.7: spells in the item list, one icon per ready spell, a threshold per spell

local function spellIcon(ns, k) -- k-th spell icon (1 = the group's own button)
  local b = buttons(ns)
  local i = k == 1 and SPELL_SLOT or #ns.GROUPS + k - 1
  return slotVisible(ns, i), b[i]
end

test("every ready spell past its threshold gets its own icon; the auto bar has room for each", function()
  local ns = M.load(nil, { class = "MAGE" })
  spellApis({ 12051, 1259823 })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.6; M.tick()
  local v1, b1 = spellIcon(ns, 1)
  ok(v1, "Eureka! (90 %) not lit at 60 %")
  ok(not spellIcon(ns, 2), "Evocation (35 %) lit at 60 %")
  M.state.manaPct = 0.3; M.tick()
  ok(spellIcon(ns, 1) and spellIcon(ns, 2), "not both lit at 30 %")
  local _, b2 = spellIcon(ns, 2)
  -- highest threshold first: lit icons come first, an unlit one never leaves a gap before them
  eq(b1.layers[1].icon.texture, "tex1259823"); eq(b2.layers[1].icon.texture, "tex12051")
  ok(b2.outer.points[1][4] > b1.outer.points[1][4], "second spell icon not next to the first")
  -- the auto bar has room for every spell icon (a column must not run past the bar)
  local before = ns.AutoBarLength()
  ns.Spells.SetEnabled(ns.SPELLS[1], false) -- Evocation off
  M.tick()
  ok(not spellIcon(ns, 2), "switched-off spell still has an icon")
  eq(ns.AutoBarLength(), before - ns.db.iconSize - (ns.db.iconGap or 6), "bar keeps room for a switched-off spell")
  noSpellApis()
end)

test("each spell has its own threshold; a switched-off group hides every spell icon", function()
  local ns = M.load(nil, { class = "MAGE" })
  spellApis({ 12051, 1259823 })
  ns.Spells.Rebuild()
  ns.Spells.SetThreshold(ns.SPELLS[1], 0.7) -- Evocation
  M.state.manaPct = 0.6; M.tick()
  ok(spellIcon(ns, 1) and spellIcon(ns, 2), "own threshold ignored")
  ns.db.enabled.spell = false; M.tick()
  ok(not buttons(ns)[SPELL_SLOT].outer.shown and not buttons(ns)[#ns.GROUPS + 1].outer.shown,
    "spell icons left with the group off")
  noSpellApis()
end)

test("old common spell threshold: a changed one is kept for every spell, 50 % gives the defaults", function()
  local saved = { dbVersion = 9, profiles = { Shared = { spellThreshold = 0.3 }, ["Kesa-Forever"] = { spellThreshold = 0.5 } },
    chars = {} }
  local ns = M.load(saved)
  local sh, own = saved.profiles.Shared, saved.profiles["Kesa-Forever"]
  eq(sh.spellThreshold, nil); eq(own.spellThreshold, nil)
  eq(sh.spellThr.evocation, 0.3); eq(sh.spellThr.eureka, 0.3)
  eq(sh.spellThr.lifetap, nil, "Life Tap got a threshold")
  eq(next(own.spellThr or {}), nil, "untouched 50 % copied")
  eq(saved.dbVersion, 10)
end)

test("item list: spells of the class with their state, threshold -/+ and on/off", function()
  local ns = M.load(nil, { class = "MAGE", level = 10 })
  spellApis({ 1259823 }, { learned = { [12051] = 20 }, names = { [12051] = "Evocation", [1259823] = "Eureka!" } })
  ns.Spells.Rebuild()
  ns.ToggleLibrary(true)
  local rows = M.upvalue(M.upvalue(ns.ToggleLibrary, "RefreshRows"), "rows")
  local evo, eur, n = nil, nil, 0
  for _, r in ipairs(rows) do
    if r.sp and r.frame.shown then
      n = n + 1
      if r.sp.key == "evocation" then evo = r end
      if r.sp.key == "eureka" then eur = r end
    end
  end
  eq(n, 2, "spells listed (Evocation, Eureka!; no other class or race)")
  ok(evo.owned.text:find(ns.L.libLevel:format(20), 1, true), "level reason: " .. evo.owned.text)
  ok(eur.owned.text:find(ns.L.libKnown, 1, true), "known: " .. eur.owned.text)
  eq(eur.amount.text, ns.L.libSpellThr:format(90))
  eur.minus.scripts.OnClick(eur.minus)
  eq(eur.amount.text, ns.L.libSpellThr:format(85), "- did not lower the threshold")
  ok(math.abs(ns.db.spellThr.eureka - 0.85) < 1e-9, "stored threshold")
  for _ = 1, 3 do eur.plus.scripts.OnClick(eur.plus) end
  ok(not eur.plus:IsEnabled(), "+ not greyed out at 95 %")
  eur.cb:SetChecked(false); eur.cb.scripts.OnClick(eur.cb)
  eq(ns.db.spellOff.eureka, true, "spell not switched off")
  ok(not ns.Spells.AnyActive(), "switched-off spell still active")
  noSpellApis()
end)

test("item list: why a spell is missing (level, talent, trainer); Life Tap fits instead of a threshold", function()
  local ns = M.load(nil, { class = "PRIEST", level = 30 })
  spellApis({}, { learned = {} })
  ns.Spells.Rebuild()
  eq(select(1, ns.Spells.Status(ns.SPELLS[5])), "talent", "Inner Focus is a talent")
  ns = M.load(nil, { class = "MAGE", level = 30 })
  spellApis({}, { learned = { [12051] = 20 } })
  ns.Spells.Rebuild()
  eq(ns.Spells.Status(ns.SPELLS[1]), "trainer", "level reached, not learned")
  ns = M.load(nil, { class = "WARLOCK" })
  spellApis({ 1454 }, { desc = { [1454] = "Converts 300 Health into 300 Mana." } })
  ns.Spells.Rebuild()
  ns.ToggleLibrary(true)
  local rows = M.upvalue(M.upvalue(ns.ToggleLibrary, "RefreshRows"), "rows")
  local tap
  for _, r in ipairs(rows) do if r.sp and r.sp.key == "lifetap" and r.frame.shown then tap = r end end
  ok(tap, "Life Tap not listed")
  eq(tap.amount.text, ns.L.libSpellFit)
  ok(not tap.minus.shown and not tap.plus.shown, "Life Tap has -/+")
  noSpellApis()
end)

test("a spell on cooldown has no mark on the bar; every ready spell has its own", function()
  local ns = M.load(nil, { class = "MAGE" })
  local cds = spellApis({ 12051, 1259823 })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.95; M.tick()
  local ticks = bar(ns).ticks[SPELL_SLOT]
  ok(ticks[1].front.shown and ticks[2].front.shown, "not one mark per ready spell")
  cds[12051], cds[1259823] = { 90, 480 }, { 95, 120 } -- both on cooldown
  at(100, function() M.tick() end)
  ok(not ticks[1].front.shown and not ticks[2].front.shown, "mark shown while every spell is on cooldown")
  noSpellApis()
end)

test("a bar set shorter than the icon column: the texts go beside the bar, away from the icons", function()
  local ns = M.load({ vertical = true, iconSize = 48, iconGap = 6, barLength = 100 }, { class = "MAGE" })
  spellApis({ 12051, 1259823 })
  ns.Spells.Rebuild()
  M.tick()
  local b = bar(ns)
  local p = b.manaBox.points[1]
  eq(p[1], "BOTTOMRIGHT", "bar left of the icons: texts not left of the bar")
  eq(p[3], "BOTTOMLEFT")
  ok(p[4] < 0, "texts not outside the bar")
  ns.db.barSide = "right"; ns.Layout(true)
  p = b.manaBox.points[1]
  eq(p[1], "BOTTOMLEFT", "bar right of the icons: texts not right of the bar"); eq(p[3], "BOTTOMRIGHT")
  ns.db.barLength = 0; ns.Layout(true) -- auto: the bar has room for every icon, texts under it
  p = b.manaBox.points[1]
  eq(p[1], "TOP"); eq(p[3], "BOTTOM"); eq(p[5], -4)
  noSpellApis()
end)

-- 0.8.8: icons show before their cooldown ends (db.cdShow seconds), grey, counting down

test("a potion shows db.cdShow seconds before its cooldown ends: grey, no glow, the game's countdown", function()
  local ns = M.load({ cdShow = 10 }, { bags = POT })
  M.state.manaPct = 0.2
  M.state.cooldowns[3385] = { 0, 120 } -- ends at 120; GetTime is 100: 20 s left
  M.tick()
  ok(not buttons(ns)[1].outer.shown, "shown 20 s before (setting 10 s)")
  M.state.time = 112 -- 8 s left
  M.tick()
  local vis, l = slotVisible(ns, 1)
  ok(vis, "not shown 8 s before its cooldown ends")
  ok(l.icon.desaturated, "cooling potion not grey")
  ok(not l.glow.shown, "cooling potion glows")
  eq(l.sweep.cdStart, 0); eq(l.sweep.cdDur, 120)
  eq(l.sweep.hideNumbers, false, "no countdown numbers")
  M.state.time = 121 -- ready
  M.tick()
  vis, l = slotVisible(ns, 1)
  ok(vis and not l.icon.desaturated and l.glow.shown, "ready potion not lit")
  M.state.time = nil
end)

test("cdShow 0: nothing shows before it is ready; a wand lock still has no numbers", function()
  local ns = M.load({ cdShow = 0 }, { bags = POT })
  M.state.manaPct = 0.2
  M.state.cooldowns[3385] = { 99, 2 } -- a wand shot's short lock
  M.tick()
  local vis, l = slotVisible(ns, 1)
  ok(vis, "potion hidden by a wand lock")
  eq(l.sweep.hideNumbers, true, "numbers on a wand lock")
  M.state.cooldowns[3385] = { 0, 101 } -- 1 s left of its own cooldown
  M.tick()
  ok(not buttons(ns)[1].outer.shown, "shown before ready with the setting off")
end)

test("a spell shows before its cooldown ends, counted from the cast in combat, grey with numbers", function()
  local ns = M.load({ cdShow = 10 }, { class = "MAGE" })
  spellApis({ 12051 }, { base = { [12051] = 480 } })
  ns.Spells.Rebuild()
  M.state.manaPct = 0.2; M.tick()
  ok(spellSlot(ns), "ready Evocation hidden")
  spellApis({ 12051 }, { secretCd = true, base = { [12051] = 480 } })
  M.state.combat = true
  M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 12051)
  at(560, function() M.tick() end) -- 20 s left
  ok(not buttons(ns)[SPELL_SLOT].outer.shown, "shown 20 s before")
  at(575, function() M.tick() end) -- 5 s left
  local vis, l = spellSlot(ns)
  ok(vis, "not shown 5 s before")
  ok(l.icon.desaturated and not l.glow.shown, "cooling spell not grey or still glowing")
  eq(l.sweep.cdDur, 480); eq(l.sweep.hideNumbers, false)
  M.state.combat = false
  noSpellApis()
end)

test("settings: 'Show before ready' sits above 'Show only in combat', 0 to 60 s in steps of 5", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  local st, combat
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.minus and w.label and w.label.text == ns.L.optCdShow .. ":" then st = w end
    if w.label and w.label.text == ns.L.optCombat then combat = w end
  end
  ok(st and combat, "settings not found")
  ok(st.label.points[1][5] > combat.points[1][5], "not above 'Show only in combat'")
  ok(st.value.points[1][5] < 0 and st.minus.points[1][5] < 0, "value and -/+ not on the line under the label")
  ok(combat.points[1][5] <= st.label.points[1][5] - 48, "'Show only in combat' not under the value line")
  eq(st.value.text, ns.L.cdShowSec:format(5), "default not 5 s")
  st.minus.scripts.OnClick(st.minus)
  eq(ns.db.cdShow, 0); eq(st.value.text, ns.L.cdShowOff)
  for _ = 1, 20 do st.plus.scripts.OnClick(st.plus) end
  eq(ns.db.cdShow, 60, "not capped at 60 s")
end)

-- data checked in game on 14 Oct 2026 ------------------------------------------------------
local function groupIndex(ns, key)
  for i, g in ipairs(ns.GROUPS) do if g.key == key then return i end end
end
local function listed(ns, key, id)
  for _, it in ipairs(ns.FullList(groupIndex(ns, key))) do if it.id == id then return it end end
end

test("battleground draughts share the potion cooldown: they are in the potion group", function()
  local ns = M.load(nil, { bags = POT })
  for _, id in ipairs({ 17351, 17352 }) do
    local it = listed(ns, "potion", id)
    ok(it and it.pvp, "draught " .. id .. " not a battleground potion")
    ok(not listed(ns, "herb", id), "draught " .. id .. " still with its own cooldown")
  end
end)

test("the three orbs are for mages only (their tooltip says Classes: Mage)", function()
  local ns = M.load(nil, { bags = POT, class = "PRIEST" })
  for _, id in ipairs({ 7507, 7508, 7515 }) do ok(not listed(ns, "gear", id), "orb " .. id .. " for a priest") end
  ns = M.load(nil, { bags = POT, class = "MAGE" })
  for _, id in ipairs({ 7507, 7508, 7515 }) do ok(listed(ns, "gear", id), "orb " .. id .. " missing for a mage") end
end)
