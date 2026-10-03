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

test("auto bar length does not depend on lit icons or switched-off groups", function()
  local ns = M.load({ vertical = true, iconSize = 48 }, { bags = POT })
  M.tick(); local h1 = bar(ns).h
  ns.db.enabled.rune = false; ns.db.test = true; M.tick()
  eq(bar(ns).h, h1)
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

test("old FMF macros are removed once macro data is loaded", function()
  local ns = M.load({ dbVersion = 3, macros = true },
    { macros = { FMF_Potion = 3, Mine = 5 }, macrosLoaded = false })
  ok(M.state.macros.FMF_Potion, "deleted before load?")
  M.state.macrosLoaded = true
  M.Fire("UPDATE_MACROS")
  ok(not M.state.macros.FMF_Potion, "FMF_Potion still there")
  ok(M.state.macros.Mine, "user macro deleted")
end)

test("macro cleanup also runs for users upgraded by 0.6.7", function()
  local ns = M.load({ dbVersion = 4 }, { macros = { FMF_Rune = 2 } })
  M.Fire("UPDATE_MACROS")
  ok(not M.state.macros.FMF_Rune)
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
  ok(not bar(ns).regen.shown, "regen text shown while off")
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

test("mana text: number, percentage, both and none", function()
  withScale100(function()
    local ns = M.load({ manaText = "percent" }, { bags = POT })
    M.state.manaPct = 0.89; M.tick()
    eq(bar(ns).text.text, "89%")
    ns.db.manaText = "both"; ns.db.vertical = false; M.tick()
    eq(bar(ns).text.text, "89%   890 / 1000")
    ns.db.vertical = true; M.tick()
    eq(bar(ns).text.text, "89%\n890 / 1000", "column: two lines")
    ns.db.manaText = "none"; M.tick()
    eq(bar(ns).text.text, "")
    ns.db.manaText = "number"; M.tick()
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
