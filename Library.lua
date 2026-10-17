-- Full Mana Forever - item list window: everything the addon supports, by category,
-- with per-item on/off and adding your own items to a category.

local _, ns = ...
local L = ns.L
local ui = ns.UI        -- Options.lua is loaded first (TOC order)
local lib, scroll, content, sbar
local reg = {}          -- window widgets that need Refresh()
local rowReg = {}       -- row checkboxes (one per pooled row)
local rows = {}         -- pooled rows: frames are created once and reused
local headers = {}      -- pooled category headers
local W, H, PAD, ROW = 620, 600, 16, 30
local CW = W - 2 * PAD - 22 -- list width before the scroll area knows its real size
local EDGE = 8              -- free space between the texts and the right edge of the list
local NAME_W = 290          -- item name column (long names end in "...")
local AMOUNT_X, AMOUNT_W = 355, 84 -- the "up to N" column

local function OwnedText(it, group)
  if group.equipped then
    local eq = ns.IsEquipped(it.id)
    if eq then return "|cff66ff66" .. L.libEquipped .. "|r" end
    return "|cff888888" .. L.libNotEquipped .. "|r"
  end
  -- the other ID of the same item (Forever's level-1 copy) counts too, and is usable
  local copies = ns.CopyCount(it)
  if copies > 0 then
    local own = C_Item.GetItemCount(it.id)
    if issecretvalue and issecretvalue(own) then own = 0 end
    return ("|cff66ff66x%d|r"):format(copies + (own or 0))
  end
  -- too high for you: say why the addon never suggests it
  local need = ns.LevelTooLow(it)
  if need then return "|cffff5555" .. L.libLevel:format(need) .. "|r" end
  local n = C_Item.GetItemCount(it.id)
  if issecretvalue and issecretvalue(n) then return "" end
  if n and n > 0 then return ("|cff66ff66x%d|r"):format(n) end
  return "|cff888888" .. L.libMissing .. "|r"
end

-- own spells: learned, or why not yet (level from the game, talent, trainer)
local function SpellStatusText(sp)
  local st, need, talent = ns.Spells.Status(sp)
  if st == "known" then return "|cff66ff66" .. L.libKnown .. "|r" end
  if st == "level" then
    return "|cffff5555" .. L.libLevel:format(need) .. (talent and (", " .. L.libTalent) or "") .. "|r"
  end
  if st == "talent" then return "|cffff5555" .. L.libTalent .. "|r" end
  return "|cff888888" .. L.libTrainer .. "|r"
end

local SPELL_STEP, SPELL_LO, SPELL_HI = 0.05, 0.10, 0.95

local function SpellID(sp) return ns.Spells.ID(sp) or sp.id end

local function RowOnEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if self.sp then
    pcall(GameTooltip.SetSpellByID, GameTooltip, SpellID(self.sp))
  else
    pcall(GameTooltip.SetItemByID, GameTooltip, self.it.id)
  end
  GameTooltip:Show()
end

-- a tooltip whose text follows the row (a pooled row shows an item or a spell)
local function RowTip(frame, fn)
  if frame.SetMotionScriptsWhileDisabled then frame:SetMotionScriptsWhileDisabled(true) end
  frame:SetScript("OnEnter", function(self)
    local title, text = fn()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(text, 0.82, 0.82, 0.82, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function RowOnLeave() GameTooltip:Hide() end

local function NewRow()
  local r = {}
  local row = CreateFrame("Frame", nil, content)
  row:SetHeight(ROW - 2) -- the width follows the list (see BuildContent)
  row:EnableMouse(true)
  row:SetScript("OnEnter", RowOnEnter)
  row:SetScript("OnLeave", RowOnLeave)
  local hl = row:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.04)

  ui.WithRegistry(rowReg, function()
    r.cb = ui.Check(row, "", function()
      if row.sp then return ns.Spells.Enabled(row.sp) end
      return ns.IsItemEnabled(row.it)
    end, function(v)
      if row.sp then ns.Spells.SetEnabled(row.sp, v) else ns.SetItemEnabled(row.it.id, v) end
    end, L.tipItemCb)
  end)
  r.cb:SetPoint("LEFT", 0, 0)
  r.cb.label:Hide()
  RowTip(r.cb, function()
    local name = r.name:GetText() or ""
    return name, row.sp and L.tipSpellCb or L.tipItemCb
  end)

  r.icon = row:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(24, 24)
  r.icon:SetPoint("LEFT", r.cb, "RIGHT", 4, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  r.name = ui.Label(row, "", "GameFontHighlight")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.name:SetWidth(NAME_W)
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  -- notes after the name ("own", "sleep 12 s!", "BG only") are never cut: in long (localized)
  -- names the name itself ends in "..."; the full name is in the item's tooltip
  r.tag = ui.Label(row, "", "GameFontHighlight")
  r.tag:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
  if r.tag.SetWordWrap then r.tag:SetWordWrap(false) end

  r.amount = ui.Label(row, "", "GameFontHighlightSmall")
  r.amount:SetPoint("LEFT", row, "LEFT", AMOUNT_X, 0)
  r.amount:SetWidth(AMOUNT_W)
  if r.amount.SetWordWrap then r.amount:SetWordWrap(false) end
  -- a spell's threshold explains itself; over an item the item's own tooltip stays
  -- (its right edge is set per row: it must end before the - / + buttons, see RefreshRows)
  local amountTip = CreateFrame("Frame", nil, row)
  r.amountTip = amountTip
  amountTip:SetPoint("TOPLEFT", r.amount, "TOPLEFT")
  amountTip:EnableMouse(true)
  amountTip:SetScript("OnEnter", function(self)
    if not row.sp then return RowOnEnter(row) end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if row.sp.fit then
      GameTooltip:SetText(L.libSpellFit, 1, 1, 1)
      GameTooltip:AddLine(L.tipSpellFit, 0.82, 0.82, 0.82, true)
    else
      GameTooltip:SetText(L.optSpellThr, 1, 1, 1)
      GameTooltip:AddLine(L.tipSpellThr, 0.82, 0.82, 0.82, true)
    end
    GameTooltip:Show()
  end)
  amountTip:SetScript("OnLeave", RowOnLeave)

  -- "not in bags" gets the rest of the row: it can never run into the amount
  r.owned = ui.Label(row, "", "GameFontHighlightSmall")
  r.owned:SetJustifyH("RIGHT")
  if r.owned.SetWordWrap then r.owned:SetWordWrap(false) end

  -- own spells: their mana threshold, - / + next to it (Life Tap: "when it fits", no buttons)
  local function Step(d)
    local sp = row.sp
    local v = ns.Spells.Threshold(sp)
    v = math.floor((v + d) / SPELL_STEP + 0.5) * SPELL_STEP
    ns.Spells.SetThreshold(sp, math.max(SPELL_LO, math.min(SPELL_HI, v)))
    r.Refresh()
  end
  r.minus = ui.Button(row, "-", 18, 18)
  r.minus:SetPoint("LEFT", row, "LEFT", AMOUNT_X + 44, 0)
  r.minus:SetScript("OnClick", function() Step(-SPELL_STEP) end)
  r.plus = ui.Button(row, "+", 18, 18)
  r.plus:SetPoint("LEFT", r.minus, "RIGHT", 2, 0)
  r.plus:SetScript("OnClick", function() Step(SPELL_STEP) end)
  ui.Tip(r.minus, L.optSpellThr, L.tipSpellThr)
  ui.Tip(r.plus, L.optSpellThr, L.tipSpellThr)
  -- the buttons sit inside the amount column: above its tooltip area, or part of each
  -- button would not take a click (owner, 17 Oct)
  r.minus:SetFrameLevel(amountTip:GetFrameLevel() + 2)
  r.plus:SetFrameLevel(amountTip:GetFrameLevel() + 2)

  r.del = ui.Button(row, "x", 20, 18)
  r.del:SetPoint("RIGHT", row, "RIGHT", -EDGE, 0)
  r.del:SetScript("OnClick", function() ns.RemoveCustom(row.it.id) end)
  ui.Tip(r.del, L.libRemove, L.tipItemDel)

  r.frame = row
  -- texts that change while the list is open (name, status, threshold, tick)
  r.Refresh = function()
    if r.sp then
      local sp = r.sp
      r.name:SetWidth(NAME_W)
      r.name:SetText(ns.Spells.Name(SpellID(sp)) or "?")
      r.tag:SetText("")
      r.owned:SetText(SpellStatusText(sp))
      if sp.fit then
        r.amount:SetText(L.libSpellFit)
      else
        local v = ns.Spells.Threshold(sp)
        r.amount:SetText(L.libSpellThr:format(math.floor(v * 100 + 0.5)))
        r.minus:SetEnabled(v > SPELL_LO + 0.001)
        r.plus:SetEnabled(v < SPELL_HI - 0.001)
      end
    elseif r.it then
      local tags = {}
      if r.it.custom then tags[#tags + 1] = "|cff4fa3ff(" .. L.libOwn .. ")|r" end
      if r.it.sleep then tags[#tags + 1] = "|cffff8844" .. L.libSleep .. "|r" end
      if r.it.pvp then tags[#tags + 1] = "|cffaaaaaa" .. L.libPvp .. "|r" end
      r.tag:SetText(table.concat(tags, " "))
      local room = NAME_W - (#tags > 0 and (r.tag:GetStringWidth() or 0) + 4 or 0)
      r.name:SetWidth(NAME_W)
      r.name:SetText(ui.ItemName(r.it.id))
      r.name:SetWidth(math.max(40, math.min(r.name:GetStringWidth() or room, room)))
      r.owned:SetText(OwnedText(r.it, r.group))
    end
    r.cb.Refresh()
  end
  return r
end

local function Header(k)
  local h = headers[k]
  if h then return h end
  h = { label = ui.Label(content, "", "GameFontNormal"), line = content:CreateTexture(nil, "ARTWORK") }
  h.line:SetColorTexture(0.3, 0.55, 1, 0.5)
  h.line:SetHeight(1)
  h.line:SetPoint("LEFT", h.label, "RIGHT", 6, 0)
  h.line:SetPoint("RIGHT", content, "RIGHT", 0, 0)
  headers[k] = h
  return h
end

local function UpdateScrollbar()
  if not (sbar and scroll and content) then return end
  local view = scroll:GetHeight() or 0
  local total = content:GetHeight() or 0
  local range = math.max(0, total - view)
  sbar:SetMinMaxValues(0, range)
  if range <= 0 then
    sbar:Hide()
  else
    sbar:Show()
    -- thumb height proportional to the visible part of the list
    local h = sbar:GetHeight() or view
    sbar.thumb:SetHeight(math.max(24, h * view / total))
  end
  sbar:SetValue(math.min(scroll:GetVerticalScroll() or 0, range))
end

-- lays the current item lists out in the pooled rows (no new frames after the first build)
local function BuildContent()
  local y, n, hn = -2, 0, 0
  for gi, group in ipairs(ns.GROUPS) do
    local spells = group.spells and ns.Spells.ListForMe()
    if ns.ForMyClass(group) and (not spells or #spells > 0) then
      hn = hn + 1
      local h = Header(hn)
      h.label:SetText(L["grp_" .. group.key])
      h.label:ClearAllPoints()
      h.label:SetPoint("TOPLEFT", 0, y)
      h.label:Show(); h.line:Show()
      y = y - 24
      local list = spells
      if not list then
        list = {}
        -- a second ID of the same item is one row with it (Data.lua "same")
        for _, e in ipairs(ns.FullList(gi)) do if not e.same then list[#list + 1] = e end end
      end
      for _, entry in ipairs(list) do
        n = n + 1
        local r = rows[n] or NewRow()
        rows[n] = r
        local sp = spells and entry or nil
        local it = not spells and entry or nil
        r.it, r.sp, r.group, r.frame.it, r.frame.sp = it, sp, group, it, sp
        r.frame:ClearAllPoints()
        r.frame:SetPoint("TOPLEFT", 0, y)
        r.frame:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        if sp then
          r.icon:SetTexture(ns.Spells.Texture(SpellID(sp)))
        else
          r.icon:SetTexture(C_Item.GetItemIconByID(it.id))
          if it.pct then
            r.amount:SetText(L.libRestorePct:format(math.floor(it.pct * 100 + 0.5)))
          else
            r.amount:SetText(L.libRestore:format(it.max))
          end
        end
        local steps = sp and not sp.fit or false
        r.minus:SetShown(steps)
        r.plus:SetShown(steps)
        r.amountTip:ClearAllPoints()
        r.amountTip:SetPoint("TOPLEFT", r.amount, "TOPLEFT")
        if steps then
          r.amountTip:SetPoint("BOTTOMRIGHT", r.minus, "BOTTOMLEFT", -2, 0)
        else
          r.amountTip:SetPoint("BOTTOMRIGHT", r.amount, "BOTTOMRIGHT")
        end
        r.owned:ClearAllPoints()
        r.owned:SetPoint("LEFT", r.frame, "LEFT", AMOUNT_X + AMOUNT_W + 4, 0)
        r.owned:SetPoint("RIGHT", r.frame, "RIGHT", it and it.custom and -(28 + EDGE) or -EDGE, 0)
        r.del:SetShown(it and it.custom and true or false)
        r.frame:Show()
        y = y - ROW
      end
      y = y - 8
    end
  end
  for k = n + 1, #rows do rows[k].frame:Hide(); rows[k].it, rows[k].sp = nil, nil end
  for k = hn + 1, #headers do headers[k].label:Hide(); headers[k].line:Hide() end
  content:SetHeight(-y + 4)
  UpdateScrollbar()
end

local function RefreshRows()
  for _, r in ipairs(rows) do
    if r.it or r.sp then r.Refresh() end
  end
  for _, w in ipairs(reg) do w.Refresh() end
end

local function Build(point)
  wipe(reg)
  lib = CreateFrame("Frame", "FullManaForeverItems", UIParent)
  lib:SetSize(W, H)
  if point and point[1] then
    lib:SetPoint(point[1], UIParent, point[3], point[4], point[5])
  else
    lib:SetPoint("CENTER", 40, 0)
  end
  lib:SetFrameStrata("DIALOG")
  lib:SetToplevel(true)
  lib:SetMovable(true)
  lib:EnableMouse(true)
  lib:SetClampedToScreen(true)
  lib:RegisterForDrag("LeftButton")
  lib:SetScript("OnDragStart", lib.StartMoving)
  lib:SetScript("OnDragStop", lib.StopMovingOrSizing)
  lib:Hide()
  -- in game a new frame does not take over a name an older one already has (the language
  -- change builds the windows anew): the name is set here, else Esc looks at the old frame
  ns.EscListed(lib, "FullManaForeverItems")
  ns.RegisterPopup(lib, "items") -- over the settings when they are open

  local bg = lib:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.06, 0.09, 1)
  local top = lib:CreateTexture(nil, "ARTWORK")
  top:SetPoint("TOPLEFT")
  top:SetPoint("TOPRIGHT")
  top:SetHeight(2)
  top:SetColorTexture(0.3, 0.55, 1, 0.9)

  local title = ui.Label(lib, L.libTitle, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", PAD, -12)
  local close = ui.Button(lib, "X", 22)
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() lib:Hide() end)
  ui.Tip(close, L.optClose, L.tipClose)

  -- scrolling list
  scroll = CreateFrame("ScrollFrame", nil, lib)
  scroll:SetPoint("TOPLEFT", PAD, -44)
  scroll:SetPoint("BOTTOMRIGHT", -PAD - 14, 128)
  scroll:EnableMouseWheel(true)
  local sbg = lib:CreateTexture(nil, "BORDER")
  sbg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -4, 4)
  sbg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 18, -4)
  sbg:SetColorTexture(0, 0, 0, 0.25)

  -- visible scrollbar: a track with a draggable thumb whose size shows how much is hidden
  sbar = CreateFrame("Slider", nil, lib)
  sbar:EnableMouse(true) -- without a template a slider does not take the mouse
  if sbar.SetObeyStepOnDrag then sbar:SetObeyStepOnDrag(true) end
  sbar:SetOrientation("VERTICAL")
  sbar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
  sbar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
  sbar:SetWidth(10)
  local track = sbar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(0.25, 0.27, 0.33, 0.9)
  local thumb = sbar:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(0.3, 0.55, 1, 0.95)
  thumb:SetSize(10, 40)
  sbar:SetThumbTexture(thumb)
  sbar.thumb = thumb
  sbar:SetMinMaxValues(0, 0)
  sbar:SetValueStep(1)
  sbar:SetValue(0)
  sbar:SetScript("OnValueChanged", function(_, v)
    if scroll:GetVerticalScroll() ~= v then scroll:SetVerticalScroll(v) end
  end)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    local v = math.min(range, math.max(0, self:GetVerticalScroll() - delta * 45))
    self:SetVerticalScroll(v)
    sbar:SetValue(v)
  end)
  sbar:EnableMouseWheel(true)
  sbar:SetScript("OnMouseWheel", function(_, delta) scroll:GetScript("OnMouseWheel")(scroll, delta) end)

  -- add own item
  local addTitle = ui.Label(lib, L.libAdd, "GameFontNormal")
  addTitle:SetPoint("BOTTOMLEFT", lib, "BOTTOMLEFT", PAD, 100)
  local hint = ui.Label(lib, L.optCustomHint, "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", addTitle, "BOTTOMLEFT", 0, -4)
  hint:SetWidth(W - 2 * PAD)

  local idLabel = ui.Label(lib, L.optId, "GameFontHighlightSmall")
  idLabel:SetPoint("BOTTOMLEFT", lib, "BOTTOMLEFT", PAD, 48)
  local idBox = ui.Edit(lib, 80)
  idBox:SetPoint("LEFT", idLabel, "LEFT", 100, 0)
  local amLabel = ui.Label(lib, L.optAmount, "GameFontHighlightSmall")
  amLabel:SetPoint("LEFT", idLabel, "LEFT", 200, 0)
  local amBox = ui.Edit(lib, 70)
  amBox:SetPoint("RIGHT", lib, "RIGHT", -PAD, 0)
  amBox:SetPoint("TOP", idBox, "TOP", 0, 0)
  ui.TipBoth(lib, idLabel, idBox, L.optId, L.tipItemId)
  ui.TipBoth(lib, amLabel, amBox, L.optAmount, L.tipItemAmount)

  local catLabel = ui.Label(lib, L.libCategory, "GameFontHighlightSmall")
  catLabel:SetPoint("BOTTOMLEFT", lib, "BOTTOMLEFT", PAD, 18)
  local chosen = "potion"
  local entries = {}
  for _, g in ipairs(ns.GROUPS) do
    if ns.ForMyClass(g) and not g.spells then entries[#entries + 1] = { value = g.key, text = L["grp_" .. g.key] } end
  end
  local cat
  ui.WithRegistry(reg, function()
    -- RefreshRows also refreshes this dropdown's text
    cat = ui.Dropdown(lib, 220, entries, function() return L["grp_" .. chosen] end,
      function(v) chosen = v; RefreshRows() end)
  end)
  cat:SetPoint("LEFT", catLabel, "LEFT", 100, 0)
  ui.TipBoth(lib, catLabel, cat, L.libCategory, L.tipItemCat)
  cat.Refresh()

  local add = ui.Button(lib, L.optAdd, 100)
  add:SetPoint("BOTTOMRIGHT", lib, "BOTTOMRIGHT", -PAD, 14)
  -- AddCustom checks both fields, prints what is wrong and refreshes this list
  local function DoAdd()
    if ns.AddCustom(idBox:GetText(), amBox:GetText(), chosen) then
      idBox:SetText("")
      amBox:SetText("")
      idBox:ClearFocus()
      amBox:ClearFocus()
    end
  end
  add:SetScript("OnClick", DoAdd)
  ui.Tip(add, L.optAdd, L.tipItemAdd)
  idBox:SetScript("OnEnterPressed", function() amBox:SetFocus() end)
  amBox:SetScript("OnEnterPressed", DoAdd)

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CW, 10)
  -- the list is exactly as wide as the visible scroll area, whatever the UI scale:
  -- nothing can stick out under the scrollbar and get cut off
  local function FitContent()
    local w = scroll:GetWidth() or 0
    if w > 0 then content:SetWidth(w) end
  end
  scroll:SetScript("OnSizeChanged", FitContent)
  FitContent()
  scroll:SetScrollChild(content)
  wipe(rows); wipe(headers); wipe(rowReg)
  BuildContent()

  local acc = 0
  lib:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc > 1 then acc = 0; RefreshRows() end
  end)
end

-- rebuild the rows (after add/remove) or the whole window (after a language change)
function ns.RebuildLibrary(full)
  if not lib then return end
  if full then -- new language: the window texts are rebuilt (only on a real change)
    -- the new window opens where the old one was moved to, scrolled to the same spot
    local shown, point = lib:IsShown(), { lib:GetPoint() }
    local off = scroll:GetVerticalScroll() or 0
    lib:Hide()
    lib, scroll, content = nil, nil, nil
    Build(point)
    if shown then ns.ToggleLibrary(true) end
    -- the scroll range is only known once the new rows are laid out (next frame)
    local function restore()
      if not scroll then return end
      local v = math.min(off, scroll:GetVerticalScrollRange() or 0)
      scroll:SetVerticalScroll(v)
      UpdateScrollbar()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, restore) else restore() end
    return
  end
  local off = scroll:GetVerticalScroll()
  BuildContent()
  RefreshRows()
  scroll:SetVerticalScroll(math.min(off, scroll:GetVerticalScrollRange() or 0))
  UpdateScrollbar()
end

function ns.ToggleLibrary(forceShow)
  if not lib then Build() end
  if forceShow or not lib:IsShown() then
    if ns.EscListed then ns.EscListed(lib, "FullManaForeverItems") end
    lib:Show()
    lib:Raise() -- opened again while hidden behind another window: bring it to the front
    RefreshRows()
    if C_Timer and C_Timer.After then C_Timer.After(0, UpdateScrollbar) else UpdateScrollbar() end
  else
    lib:Hide()
  end
end
