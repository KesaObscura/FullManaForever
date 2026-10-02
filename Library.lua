-- Full Mana Forever - item list window: everything the addon supports, by category,
-- with per-item on/off and adding your own items to a category.

local _, ns = ...
local L = ns.L
local lib, scroll, content, sbar
local reg = {}          -- widgets that need Refresh()
local rows = {}         -- name / owned labels, refreshed while open
local W, H, PAD, ROW = 500, 600, 16, 30

local function UI() return ns.UI end

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

local function BuildContent()
  local ui, db = UI(), ns.db
  if content then content:Hide() end
  wipe(rows)
  content = CreateFrame("Frame", nil, scroll)
  local cw = W - 2 * PAD - 22 -- room for the scrollbar
  content:SetSize(cw, 10)
  scroll:SetScrollChild(content)

  ui.SetRegistry(reg)
  local y = -2
  for gi, group in ipairs(ns.GROUPS) do
    if ns.ForMyClass(group) then
    local h = ui.Label(content, L["grp_" .. group.key], "GameFontNormal")
    h:SetPoint("TOPLEFT", 0, y)
    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.3, 0.55, 1, 0.5)
    line:SetHeight(1)
    line:SetPoint("LEFT", h, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    y = y - 24

    for _, it in ipairs(ns.FullList(gi)) do
      local row = CreateFrame("Frame", nil, content)
      row:SetSize(cw, ROW - 2)
      row:SetPoint("TOPLEFT", 0, y)
      row:EnableMouse(true)
      row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetItemByID, GameTooltip, it.id)
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
      local hl = row:CreateTexture(nil, "BACKGROUND")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 1, 1, 0.04)

      local cb = ui.Check(row, "", function() return ns.IsItemEnabled(it) end,
        function(v) ns.SetItemEnabled(it.id, v) end)
      cb:SetPoint("LEFT", 0, 0)
      cb.label:Hide()

      local icon = row:CreateTexture(nil, "ARTWORK")
      icon:SetSize(24, 24)
      icon:SetPoint("LEFT", cb, "RIGHT", 4, 0)
      icon:SetTexture(C_Item.GetItemIconByID(it.id))
      icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

      local name = ui.Label(row, "", "GameFontHighlight")
      name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
      name:SetWidth(240)
      if name.SetWordWrap then name:SetWordWrap(false) end

      local amount = ui.Label(row, L.libRestore:format(it.max), "GameFontHighlightSmall")
      amount:SetPoint("LEFT", row, "LEFT", 305, 0)

      local owned = ui.Label(row, "", "GameFontHighlightSmall")
      owned:SetJustifyH("RIGHT")
      owned:SetPoint("RIGHT", row, "RIGHT", it.custom and -32 or -4, 0)

      if it.custom then
        local del = ui.Button(row, "x", 20, 18)
        del:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        del:SetScript("OnClick", function()
          ns.RemoveCustom(it.id)
          ns.RebuildLibrary()
        end)
      end

      rows[#rows + 1] = { it = it, group = group, name = name, owned = owned, icon = icon }
      y = y - ROW
    end
    y = y - 8
    end
  end
  ui.SetRegistry(nil)
  content:SetHeight(-y + 4)
  ns.UpdateLibraryScrollbar()
end

function ns.UpdateLibraryScrollbar()
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

local function RefreshRows()
  local ui = UI()
  for _, r in ipairs(rows) do
    local n = ui.ItemName(r.it.id)
    if r.it.custom then n = n .. " |cff4fa3ff(" .. L.libOwn .. ")|r" end
    if r.it.sleep then n = n .. " |cffff8844" .. L.libSleep .. "|r" end
    if r.it.pvp then n = n .. " |cffaaaaaa" .. L.libPvp .. "|r" end
    r.name:SetText(n)
    r.owned:SetText(OwnedText(r.it, r.group))
    if not r.icon:GetTexture() then r.icon:SetTexture(C_Item.GetItemIconByID(r.it.id)) end
  end
  for _, w in ipairs(reg) do w.Refresh() end
end

local function Build()
  local ui, db = UI(), ns.db
  wipe(reg)
  lib = CreateFrame("Frame", "FullManaForeverItems", UIParent)
  lib:SetSize(W, H)
  lib:SetPoint("CENTER", 40, 0)
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
  bg:SetColorTexture(0.05, 0.06, 0.09, 0.97)
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
  ui.SetRegistry(reg)
  local cat = ui.Dropdown(lib, 220, entries, function() return L["grp_" .. chosen] end,
    function(v) chosen = v; RefreshRows() end)
  ui.SetRegistry(nil)
  cat:SetPoint("LEFT", catLabel, "LEFT", 100, 0)
  cat.Refresh()

  local add = ui.Button(lib, L.optAdd, 100)
  add:SetPoint("BOTTOMRIGHT", lib, "BOTTOMRIGHT", -PAD, 14)
  local function DoAdd()
    local id, amount = tonumber(idBox:GetText()), tonumber(amBox:GetText())
    if id and amount and amount > 0 then
      if ns.AddCustom(id, amount, chosen) then
        idBox:SetText("")
        amBox:SetText("")
        idBox:ClearFocus()
        amBox:ClearFocus()
        ns.RebuildLibrary()
      end
    else
      ns.Print(L.itemUsage)
    end
  end
  add:SetScript("OnClick", DoAdd)
  idBox:SetScript("OnEnterPressed", function() amBox:SetFocus() end)
  amBox:SetScript("OnEnterPressed", DoAdd)

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
  if full then
    local shown = lib:IsShown()
    lib:Hide()
    lib, scroll, content = nil, nil, nil
    if shown then ns.ToggleLibrary(true) end
    return
  end
  local off = scroll:GetVerticalScroll()
  BuildContent()
  RefreshRows()
  scroll:SetVerticalScroll(math.min(off, scroll:GetVerticalScrollRange() or 0))
  ns.UpdateLibraryScrollbar()
end

function ns.ToggleLibrary(forceShow)
  if not lib then Build() end
  if forceShow or not lib:IsShown() then
    lib:Show()
    RefreshRows()
    if C_Timer and C_Timer.After then C_Timer.After(0, ns.UpdateLibraryScrollbar) else ns.UpdateLibraryScrollbar() end
  else
    lib:Hide()
  end
end
