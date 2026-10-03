local M, test, eq, ok = T.M, T.test, T.eq, T.ok

local function libReg(ns) return M.upvalue(ns.RebuildLibrary, "BuildContent") and M.upvalue(M.upvalue(ns.RebuildLibrary, "BuildContent"), "rowReg") end

test("item list: rebuilding does not pile up widgets or frames", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  ns.RebuildLibrary()
  local frames = M.created
  for _ = 1, 10 do ns.RebuildLibrary() end
  eq(M.created, frames, "frames created by 10 rebuilds:")
end)

test("item list follows /fmf item and /fmf item clear", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  SlashCmdList.FULLMANAFOREVER("item 4242 300 potion")
  local rows = M.upvalue(ns.RebuildLibrary, "rows") or M.upvalue(M.upvalue(ns.RebuildLibrary, "BuildContent"), "rows")
  local found = false
  for _, r in ipairs(rows) do if r.it and r.it.id == 4242 and r.frame.shown then found = true end end
  ok(found, "added item not listed")
  SlashCmdList.FULLMANAFOREVER("item clear")
  for _, r in ipairs(rows) do ok(not (r.it and r.it.id == 4242 and r.frame.shown), "cleared item still listed") end
end)

test("item list scrollbar takes the mouse", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  local sbar = M.upvalue(ns.ToggleLibrary, "sbar") or M.upvalue(M.upvalue(ns.ToggleLibrary, "Build"), "sbar")
  ok(sbar and sbar.mouse, "slider has no mouse")
end)

test("options: choosing the current layout or language does not rebuild the window", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  local win = FullManaForeverOptions
  local frames = M.created
  -- find the dropdowns by their list rows and pick the already active values
  local picked = 0
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.Select and w.entries then
      if w.entries[1].value == false then w.Select(ns.db.vertical); picked = picked + 1 end
      if w.entries[1].value == "auto" then w.Select(ns.db.language); picked = picked + 1 end
    end
  end
  eq(picked, 2, "dropdowns found")
  eq(FullManaForeverOptions, win, "window rebuilt")
  eq(M.created, frames, "frames created")
end)

test("options: a failing widget build leaves the registry usable", function()
  local ns = M.load(nil)
  local ui = ns.UI
  ok(ui.WithRegistry, "no WithRegistry helper")
  local mine = {}
  local okRun = pcall(ui.WithRegistry, mine, function() error("boom") end)
  ok(not okRun, "error swallowed")
  ns.ToggleOptions(true)
  eq(#mine, 0, "options widgets went into the item list registry")
end)

test("options: settings button does not touch Blizzard panels in combat", function()
  local ns = M.load(nil)
  M.state.combat = true
  _G.SettingsPanel = M.new("Frame")
  _G.Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = M.noop }
  ns.InitOptions()
  local btn = M.upvalue(ns.InitOptions, "panelButton")
  btn.scripts.OnClick(btn)
  eq(M.calls.HideUIPanel, nil, "HideUIPanel called in combat")
end)

test("options window stays on top of the item list when clicked", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  ok(FullManaForeverOptions.toplevel, "not toplevel")
end)

-- 0.6.9 options layout -------------------------------------------------------
local function steppers(ns)
  local out = {}
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.minus and w.label then out[w.label.text] = w end
  end
  return out
end

test("options: stepper buttons and dropdowns line up in fixed columns", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  local xs, n = {}, 0
  for name, s in pairs(steppers(ns)) do
    local p = s.minus.points[1]
    xs[s.x + p[4]] = name
    n = n + 1
  end
  ok(n >= 5, "steppers found: " .. n)
  local cols = 0
  for _ in pairs(xs) do cols = cols + 1 end
  eq(cols, 1, "different -/+ columns")
  local widths = {}
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.entries then widths[w.w] = true end
  end
  local nw = 0
  for _ in pairs(widths) do nw = nw + 1 end
  eq(nw, 1, "dropdown widths differ")
end)

test("options: bar length leaves auto at the auto length and returns to auto below an icon", function()
  local ns = M.load({ iconSize = 44, iconGap = 6 })
  ns.ToggleOptions(true)
  local s = steppers(ns)[ns.L.optBarLen .. ":"]
  ok(s, "bar length stepper")
  eq(ns.db.barLength, 0)
  ok(not s.minus:IsEnabled(), "minus active at auto")
  s.plus.scripts.OnClick(s.plus)
  -- priest: 4 groups -> 4*44 + 3*6 = 194, rounded up to the 20 step
  eq(ns.db.barLength, 200, "first step from auto")
  ns.db.barLength = 60
  s.minus.scripts.OnClick(s.minus)
  eq(ns.db.barLength, 0, "below the icon size")
end)

test("options: -/+ are greyed out at the limits", function()
  local ns = M.load({ iconSize = 96 })
  ns.ToggleOptions(true)
  local s = steppers(ns)[ns.L.optSize .. ":"]
  ok(not s.plus:IsEnabled(), "plus active at max")
  ok(s.minus:IsEnabled(), "minus inactive below max")
end)

test("options: empty groups keep their status on the same line", function()
  local ns = M.load(nil, { bags = { [3385] = 2 } })
  ns.ToggleOptions(true)
  local rows = M.upvalue(ns.RefreshOptions, "groupRows")
  ok(#rows >= 4, "group rows")
  local potion, rune = rows[1], rows[2]
  eq(potion.st.points[1][2], potion.cb, "potion status not below its checkbox")
  eq(rune.st.points[1][2], rune.cb.label, "empty rune status not next to the name")
  eq(rows[3].cb.points[1][5], -26, "row after an empty group is not compact")
  eq(rune.cb.points[1][5], -42, "row after a full group")
end)

test("options: settings explain themselves on hover", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  local tips = 0
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.kind == "CheckButton" and w.scripts.OnEnter then
      GameTooltip.lines = nil
      w.scripts.OnEnter(w)
      ok(GameTooltip.lines and #GameTooltip.lines[1] > 10, "empty tooltip")
      tips = tips + 1
    end
  end
  ok(tips >= 6, "checkboxes with tooltips: " .. tips)
end)

test("item list keeps its place when the language changes", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  local lib = FullManaForeverItems
  lib:ClearAllPoints()
  lib:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 123, 456)
  ns.ToggleOptions(true)
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.entries and w.entries[1].value == "auto" then w.Select("deDE") end
  end
  ok(FullManaForeverItems ~= lib, "window not rebuilt")
  local p = FullManaForeverItems.points[1]
  eq(p[1], "TOPLEFT"); eq(p[4], 123, "x"); eq(p[5], 456, "y")
  ok(FullManaForeverItems.shown, "window closed by the language change")
end)

test("item list: the owned column cannot run into the amount column", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  local rows = M.upvalue(ns.RebuildLibrary, "rows") or M.upvalue(M.upvalue(ns.RebuildLibrary, "BuildContent"), "rows")
  local r = rows[1]
  eq(#r.owned.points, 2, "owned text is not boxed between two anchors")
  local amountEnd = r.amount.points[1][4] + r.amount.w
  ok(r.owned.points[1][4] >= amountEnd, "owned column starts inside the amount column")
end)

test("options: empty gear group says nothing is equipped", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  for _, r in ipairs(M.upvalue(ns.RefreshOptions, "groupRows")) do
    if ns.GROUPS[r.i].equipped then
      ok(r.st.text:find(ns.L.stNoneGear, 1, true), "gear status: " .. tostring(r.st.text))
    end
  end
end)
