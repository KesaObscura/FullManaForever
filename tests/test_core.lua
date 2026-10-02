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
