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
local W, H, PAD, ROW = 560, 600, 16, 30
local CW = W - 2 * PAD - 22 -- list width before the scroll area knows its real size
local EDGE = 8              -- free space between the texts and the right edge of the list
local NAME_W = 230          -- item name column (long names end in "...")
local AMOUNT_X, AMOUNT_W = 295, 84 -- the "up to N" column

local function OwnedText(it, group)
  if group.equipped then
    local eq = C_Item.IsEquippedItem and C_Item.IsEquippedItem(it.id)
    if eq then return "|cff66ff66" .. L.libEquipped .. "|r" end
    return "|cff888888" .. L.libNotEquipped .. "|r"
  end
  local n = C_Item.GetItemCount(it.id)
  if issecretvalue and issecretvalue(n) then return "" end
  if n and n > 0 then return ("|cff66ff66x%d|r"):format(n) end
  return "|cff888888" .. L.libMissing .. "|r"
end

local function RowOnEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  pcall(GameTooltip.SetItemByID, GameTooltip, self.it.id)
  GameTooltip:Show()
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
    r.cb = ui.Check(row, "", function() return ns.IsItemEnabled(row.it) end,
      function(v) ns.SetItemEnabled(row.it.id, v) end)
  end)
  r.cb:SetPoint("LEFT", 0, 0)
  r.cb.label:Hide()

  r.icon = row:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(24, 24)
  r.icon:SetPoint("LEFT", r.cb, "RIGHT", 4, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  r.name = ui.Label(row, "", "GameFontHighlight")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.name:SetWidth(NAME_W)
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end

  r.amount = ui.Label(row, "", "GameFontHighlightSmall")
  r.amount:SetPoint("LEFT", row, "LEFT", AMOUNT_X, 0)
  r.amount:SetWidth(AMOUNT_W)
  if r.amount.SetWordWrap then r.amount:SetWordWrap(false) end

  -- "not in bags" gets the rest of the row: it can never run into the amount
  r.owned = ui.Label(row, "", "GameFontHighlightSmall")
  r.owned:SetJustifyH("RIGHT")
  if r.owned.SetWordWrap then r.owned:SetWordWrap(false) end

  r.del = ui.Button(row, "x", 20, 18)
  r.del:SetPoint("RIGHT", row, "RIGHT", -EDGE, 0)
  r.del:SetScript("OnClick", function() ns.RemoveCustom(row.it.id) end)

  r.frame = row
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
    if ns.ForMyClass(group) then
      hn = hn + 1
      local h = Header(hn)
      h.label:SetText(L["grp_" .. group.key])
      h.label:ClearAllPoints()
      h.label:SetPoint("TOPLEFT", 0, y)
      h.label:Show(); h.line:Show()
      y = y - 24
      for _, it in ipairs(ns.FullList(gi)) do
        n = n + 1
        local r = rows[n] or NewRow()
        rows[n] = r
        r.it, r.group, r.frame.it = it, group, it
        r.frame:ClearAllPoints()
        r.frame:SetPoint("TOPLEFT", 0, y)
        r.frame:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        r.icon:SetTexture(C_Item.GetItemIconByID(it.id))
        r.amount:SetText(L.libRestore:format(it.max))
        r.owned:ClearAllPoints()
        r.owned:SetPoint("LEFT", r.frame, "LEFT", AMOUNT_X + AMOUNT_W + 4, 0)
        r.owned:SetPoint("RIGHT", r.frame, "RIGHT", it.custom and -(28 + EDGE) or -EDGE, 0)
        r.del:SetShown(it.custom and true or false)
        r.frame:Show()
        y = y - ROW
      end
      y = y - 8
    end
  end
  for k = n + 1, #rows do rows[k].frame:Hide(); rows[k].it = nil end
  for k = hn + 1, #headers do headers[k].label:Hide(); headers[k].line:Hide() end
  content:SetHeight(-y + 4)
  UpdateScrollbar()
end

local function RefreshRows()
  for _, r in ipairs(rows) do
    if r.it then
      local n = ui.ItemName(r.it.id)
      if r.it.custom then n = n .. " |cff4fa3ff(" .. L.libOwn .. ")|r" end
      if r.it.sleep then n = n .. " |cffff8844" .. L.libSleep .. "|r" end
      if r.it.pvp then n = n .. " |cffaaaaaa" .. L.libPvp .. "|r" end
      r.name:SetText(n)
      r.owned:SetText(OwnedText(r.it, r.group))
      r.cb.Refresh()
    end
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
  if UISpecialFrames then
    local listed = false
    for _, n in ipairs(UISpecialFrames) do if n == "FullManaForeverItems" then listed = true end end
    if not listed then table.insert(UISpecialFrames, "FullManaForeverItems") end
  end

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

  local catLabel = ui.Label(lib, L.libCategory, "GameFontHighlightSmall")
  catLabel:SetPoint("BOTTOMLEFT", lib, "BOTTOMLEFT", PAD, 18)
  local chosen = "potion"
  local entries = {}
  for _, g in ipairs(ns.GROUPS) do
    if ns.ForMyClass(g) then entries[#entries + 1] = { value = g.key, text = L["grp_" .. g.key] } end
  end
  local cat
  ui.WithRegistry(reg, function()
    -- RefreshRows also refreshes this dropdown's text
    cat = ui.Dropdown(lib, 220, entries, function() return L["grp_" .. chosen] end,
      function(v) chosen = v; RefreshRows() end)
  end)
  cat:SetPoint("LEFT", catLabel, "LEFT", 100, 0)
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
    lib:Show()
    RefreshRows()
    if C_Timer and C_Timer.After then C_Timer.After(0, UpdateScrollbar) else UpdateScrollbar() end
  else
    lib:Hide()
  end
end
