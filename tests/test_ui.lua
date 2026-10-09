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
      if w.entries[1].value == "auto" then w.Select(ns.acct.language); picked = picked + 1 end
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
    -- the profile switch sits in the title row, not in a column
    if w.entries and w.entries[1].value ~= "shared" then widths[w.w] = true end
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
  ok(s.plus.alpha < 0.5, "inactive plus is not faded")
  eq(s.minus.alpha, 1, "active minus is faded")
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

test("item list: rows are as wide as the visible list, nothing sticks out", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  local scroll = M.upvalue(ns.ToggleLibrary, "scroll") or M.upvalue(M.upvalue(ns.ToggleLibrary, "Build"), "scroll")
  local content = M.upvalue(ns.RebuildLibrary, "content")
  scroll:SetWidth(480)
  scroll.scripts.OnSizeChanged(scroll)
  eq(content.w, 480, "list width")
  local rows = M.upvalue(ns.RebuildLibrary, "rows") or M.upvalue(M.upvalue(ns.RebuildLibrary, "BuildContent"), "rows")
  local p = rows[1].frame.points[2]
  eq(p[1], "RIGHT"); eq(p[2], content, "row not tied to the list's right edge")
end)

test("item list keeps its scroll position when the language changes", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  local function scrollOf() return M.upvalue(ns.RebuildLibrary, "scroll") end
  scrollOf():SetVerticalScroll(120)
  ns.ToggleOptions(true)
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.entries and w.entries[1].value == "auto" then w.Select("ruRU") end
  end
  eq(scrollOf():GetVerticalScroll(), 120, "scroll after the language change")
end)

test("item list says which level an item needs", function()
  local ns = M.load(nil, { level = 16, minLevel = { [3827] = 22 }, bags = { [3827] = 2 } })
  ns.ToggleLibrary(true)
  local rows = M.upvalue(ns.RebuildLibrary, "rows") or M.upvalue(M.upvalue(ns.RebuildLibrary, "BuildContent"), "rows")
  local found
  for _, r in ipairs(rows) do
    if r.it and r.it.id == 3827 then found = r.owned.text end
  end
  ok(found and found:find(ns.L.libLevel:format(22), 1, true), "level text: " .. tostring(found))
end)

test("text with letters keeps the game's font family (no boxes for other alphabets)", function()
  local ns = M.load(nil)
  local regen = M.upvalue(ns.PositionBar, "bar").regen
  eq(regen.font, nil, "the regen text was switched to a single font file")
end)

test("options: text size of the mana numbers, the rule's seconds and the regen can be changed", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  local b = M.upvalue(ns.PositionBar, "bar")
  eq(b.manaBox.scale, 1); eq(b.fsrBox.scale, 1); eq(b.regenBox.scale, 1)
  local sizes = {}
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.minus and w.label and w.label.text == ns.L.optTextSize .. ":" then sizes[#sizes + 1] = w end
  end
  eq(#sizes, 3, "size steppers")
  sizes[1].plus.scripts.OnClick(sizes[1].plus)
  sizes[2].plus.scripts.OnClick(sizes[2].plus)
  sizes[3].minus.scripts.OnClick(sizes[3].minus)
  eq(ns.db.manaScale, 1.1); eq(ns.db.fsrScale, 1.1); eq(ns.db.regenScale, 0.9)
  eq(b.manaBox.scale, 1.1, "mana numbers not resized")
  eq(b.fsrBox.scale, 1.1, "seconds not resized")
  eq(b.regenBox.scale, 0.9, "regen not resized")
  eq(sizes[1].value.text, "110%")
  ns.ResetSize()
  eq(ns.db.manaScale, 1, "reset size kept the mana text size")
end)

test("options: + on a bar shorter than an icon grows it instead of going to auto", function()
  local ns = M.load({ iconSize = 96, barLength = 60 })
  ns.ToggleOptions(true)
  local s = steppers(ns)[ns.L.optBarLen .. ":"]
  s.plus.scripts.OnClick(s.plus)
  eq(ns.db.barLength, 100, "+ from 60 with 96 px icons")
end)

test("options: an unknown saved colour or mana text still shows a choice", function()
  local ns = M.load({ barColor = "gone", manaText = "gone" })
  ns.ToggleOptions(true)
  local texts = {}
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.entries then texts[w.entries[1].value] = w.text end
  end
  eq(texts.blue, ns.L.col_blue, "colour dropdown")
  eq(texts.number, ns.L.mtNumber, "mana text dropdown")
end)

test("item list: equipped gear is recognised the same way as by the icons", function()
  local ns = M.load(nil)
  _G.C_Item.IsEquippedItem = nil
  _G.IsEquippedItem = function() return true end
  ns.ToggleLibrary(true)
  ns.RebuildLibrary()
  local rows = M.upvalue(ns.RebuildLibrary, "rows") or M.upvalue(M.upvalue(ns.RebuildLibrary, "BuildContent"), "rows")
  local found
  for _, r in ipairs(rows) do
    if r.group and r.group.equipped and r.frame.shown then found = r.owned.text end
  end
  _G.IsEquippedItem = nil
  eq(found, "|cff66ff66" .. ns.L.libEquipped .. "|r", "gear text")
end)

test("options: switching a group off shortens the auto bar at once", function()
  local ns = M.load({ vertical = true, iconSize = 48, iconGap = 6 })
  ns.ToggleOptions(true)
  local bar = M.upvalue(ns.PositionBar, "bar")
  M.tick(); local h1 = bar.h
  local cb
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.label and w.label.text == ns.L.grp_rune and w.GetChecked then cb = w end
  end
  ok(cb, "rune checkbox")
  cb:SetChecked(false); cb.scripts.OnClick(cb)
  eq(ns.db.enabled.rune, false)
  eq(bar.h, h1 - 48 - 6, "bar length after switching runes off")
end)

test("options: regen settings stay when the bar is off; the free regen text can be switched on", function()
  local ns = M.load({ showBar = false })
  ns.ToggleOptions(true)
  local regenCb, freeCb
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.label and w.label.text == ns.L.optRegen and w.GetChecked then regenCb = w end
    if w.label and w.label.text == ns.L.optTextFree and w.GetChecked then freeCb = w end
  end
  ok(regenCb and regenCb.shown, "regen checkbox hidden with the bar off")
  ok(freeCb and freeCb.shown, "free regen checkbox missing")
  SlashCmdList.FULLMANAFOREVER("unlock")
  local box = M.upvalue(ns.PositionBar, "bar").regenBox
  ok(not box.mouse, "regen text draggable before the switch")
  freeCb:SetChecked(true); freeCb.scripts.OnClick(freeCb)
  eq(ns.db.textFree, true)
  ok(box.mouse, "regen text not draggable after the switch")
end)

test("options: 'Move texts freely' sits under unlock and only works while unlocked; resets side by side", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  local unlockCb, freeCb, reset, resetSize
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.label and w.label.text == ns.L.optUnlock then unlockCb = w end
    if w.label and w.label.text == ns.L.optTextFree then freeCb = w end
  end
  ok(unlockCb and freeCb, "unlock or free text switch missing")
  ok(freeCb.points[1][5] > -120, "free text switch not near the top")
  ok(not freeCb:IsEnabled(), "free text switch usable while locked")
  unlockCb:SetChecked(true); unlockCb.scripts.OnClick(unlockCb)
  eq(ns.db.locked, false)
  ok(freeCb:IsEnabled(), "free text switch greyed out while unlocked")
  for _, f in ipairs(M.all) do
    if f.kind == "Button" and f.text == ns.L.optReset then reset = f end
    if f.kind == "Button" and f.text == ns.L.optResetSize then resetSize = f end
  end
  ok(reset and resetSize, "reset buttons not found")
  -- equal halves side by side, together as wide as the column; the switches above them
  local rp, sp = reset.points[1], resetSize.points[1]
  eq(reset.w, resetSize.w, "reset buttons differ in width")
  eq(sp[5], rp[5], "reset size not on the row of reset position")
  eq(rp[4] + reset.w + 8, sp[4], "gap between the reset buttons")
  eq(sp[4] + resetSize.w, 440 - rp[4], "reset buttons do not fill the row")
  eq(freeCb.points[1][5], unlockCb.points[1][5], "free text switch not on the row of unlock")
  eq(freeCb.points[1][4], sp[4], "free text switch not above reset size")
end)


test("options: settings of a switched-off part stay in place, greyed out", function()
  local ns = M.load({ showBar = false, manaTextOn = false, fsr = false })
  ns.ToggleOptions(true)
  local barDD, manaDD, sizes = nil, nil, {}
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.entries and w.entries[1] and w.entries[1].value == "below" then barDD = w end
    if w.entries and w.entries[1] and w.entries[1].value == "number" then manaDD = w end
    if w.minus and w.label and w.label.text == ns.L.optTextSize .. ":" then sizes[#sizes + 1] = w end
  end
  ok(barDD and barDD.shown, "bar position hidden instead of greyed out")
  ok(not barDD:IsEnabled(), "bar position usable with the bar off")
  ok(not manaDD:IsEnabled(), "mana text list usable with the mana numbers off")
  ok(not sizes[1].plus:IsEnabled() and not sizes[1].minus:IsEnabled(), "mana size usable while off")
  ok(not sizes[2].plus:IsEnabled(), "rule size usable while off")
  ok(sizes[3].plus:IsEnabled(), "regen size greyed out although the regen is on")
  eq(sizes[1].label.color[1], 0.5, "label of a switched-off size not grey")
  ns.db.showBar, ns.db.manaTextOn = true, true
  ns.RefreshOptions()
  ok(barDD:IsEnabled() and manaDD:IsEnabled(), "settings stay grey after switching on")
  ok(sizes[1].plus:IsEnabled(), "mana size stays grey after switching on")
  eq(sizes[1].label.color[1], 1, "label stays grey after switching on")
end)


test("every control in the settings and the item list has a tooltip, also while greyed out", function()
  local ns = M.load({ custom = { { id = 12345, max = 500, group = "potion" } } })
  ns.ToggleOptions(true)
  ns.ToggleLibrary(true)
  local roots = { [_G.FullManaForeverOptions] = true, [_G.FullManaForeverItems] = true }
  local clickable = { Button = true, CheckButton = true, EditBox = true }
  local seen = 0
  for _, f in ipairs(M.all) do
    if clickable[f.kind] then
      local p, inList, inWin = f.parent, false, false
      while p do
        if p.ddList then inList = true end
        if roots[p] then inWin = true end
        p = p.parent
      end
      if inWin and not inList then
        seen = seen + 1
        local name = f.text or (f.label and f.label.text) or f.kind
        ok(f.scripts.OnEnter, "no tooltip on " .. tostring(name))
        if f.kind ~= "EditBox" then ok(f.motionWhileDisabled, "no tooltip while greyed out: " .. tostring(name)) end
      end
    end
  end
  ok(seen > 30, "too few controls found: " .. seen)
end)


test("options: the rune and spell thresholds are greyed out while their group is off", function()
  local ns = M.load({ enabled = { rune = false } })
  ns.ToggleOptions(true)
  local margin, spellThr
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.minus and w.label and w.label.text == ns.L.optMargin .. ":" then margin = w end
    if w.minus and w.label and w.label.text == ns.L.optSpellThr then spellThr = w end
  end
  ok(margin and spellThr, "thresholds not found")
  ok(not margin.plus:IsEnabled(), "rune threshold usable with runes off")
  ok(spellThr.plus:IsEnabled(), "spell threshold greyed out although spells are on")
  ns.db.enabled.rune, ns.db.enabled.spell = true, false
  ns.RefreshOptions()
  ok(margin.plus:IsEnabled(), "rune threshold stays grey after switching on")
  ok(not spellThr.plus:IsEnabled(), "spell threshold usable with spells off")
end)


test("options: a long unlock label pushes 'Move texts freely' one row down instead of covering it", function()
  local ns = M.load({ language = "ruRU" })
  ns.ToggleOptions(true)
  local unlockCb, freeCb
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.label and w.label.text == ns.L.optUnlock then unlockCb = w end
    if w.label and w.label.text == ns.L.optTextFree then freeCb = w end
  end
  eq(freeCb.points[1][4], unlockCb.points[1][4], "free text switch not under unlock")
  ok(freeCb.points[1][5] < unlockCb.points[1][5], "free text switch not one row down")
end)
