-- Full Mana Forever - options window.
-- Built without Blizzard templates on purpose: templates change between client
-- versions, and Forever is a moving target. Everything here is plain frames.

local _, ns = ...
local L = ns.L
local win, panelButton
local widgets = {}
local registry = widgets

local W, PAD = 440, 16

------------------------------------------------------------------------
-- widget helpers
------------------------------------------------------------------------
local function Label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  return fs
end

local function FitWidth(b, minW)
  local fs = b:GetFontString()
  if fs and fs.GetStringWidth then
    local need = math.ceil(fs:GetStringWidth() or 0) + 20
    b:SetWidth(math.max(minW, need))
  end
end

local function Button(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h or 22)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.16, 0.17, 0.24, 0.95)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(0.3, 0.55, 1, 0.3)
  b:SetNormalFontObject("GameFontNormalSmall")
  b:SetHighlightFontObject("GameFontHighlightSmall")
  b:SetText(text)
  FitWidth(b, w)
  return b
end

local function Check(parent, text, get, set)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(24, 24)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  cb.label = Label(parent, text)
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    ns.RefreshOptions()
  end)
  cb.Refresh = function() cb:SetChecked(get() and true or false) end
  registry[#registry + 1] = cb
  return cb
end

local function Edit(parent, w)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w, 20)
  e:SetAutoFocus(false)
  e:SetFontObject("ChatFontNormal")
  e:SetNumeric(true)
  e:SetMaxLetters(7)
  e:SetTextInsets(5, 5, 0, 0)
  local bg = e:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  return e
end

-- "Label: value [-] [+]"
local function Stepper(parent, text, get, set, step, lo, hi, fmt)
  local s = {}
  s.label = Label(parent, text)
  s.value = Label(parent, "", "GameFontNormal")
  s.minus = Button(parent, "-", 22)
  s.plus = Button(parent, "+", 22)
  s.value:SetPoint("LEFT", s.label, "RIGHT", 8, 0)
  s.minus:SetPoint("LEFT", s.label, "LEFT", 220, 0)
  s.plus:SetPoint("LEFT", s.minus, "RIGHT", 4, 0)
  local function change(d)
    local v = math.min(hi, math.max(lo, get() + d))
    set(tonumber(("%.2f"):format(v)))
    ns.RefreshOptions()
  end
  s.minus:SetScript("OnClick", function() change(-step) end)
  s.plus:SetScript("OnClick", function() change(step) end)
  s.Refresh = function() s.value:SetText(fmt(get())) end
  registry[#registry + 1] = s
  return s
end

-- Blizzard-style dropdown: a button that opens a list below it
local function Dropdown(parent, width, entries, getText, onPick)
  local dd = Button(parent, "", width)
  dd:SetWidth(width)
  local arrow = dd:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetRotation(-math.pi / 2)

  local list = CreateFrame("Frame", nil, dd)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", 0, -2)
  list:EnableMouse(true)
  local lbg = list:CreateTexture(nil, "BACKGROUND")
  lbg:SetAllPoints()
  lbg:SetColorTexture(0.03, 0.04, 0.07, 0.98)
  local edge = list:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPLEFT")
  edge:SetPoint("TOPRIGHT")
  edge:SetHeight(1)
  edge:SetColorTexture(0.3, 0.55, 1, 0.8)
  list:Hide()

  local rows, maxW = {}, width
  for i, e in ipairs(entries) do
    local r = Button(list, e.text, width, 20)
    local fs = r:GetFontString()
    if fs then
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", 10, 0)
    end
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2 - (i - 1) * 21)
    r:SetScript("OnClick", function()
      list:Hide()
      onPick(e.value)
    end)
    maxW = math.max(maxW, r:GetWidth())
    rows[i] = r
  end
  for _, r in ipairs(rows) do r:SetWidth(maxW) end
  list:SetSize(maxW + 4, #entries * 21 + 3)

  dd:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
  dd:SetScript("OnHide", function() list:Hide() end)
  dd.Refresh = function()
    dd:SetText(getText())
    dd:SetWidth(width)
    local fs = dd:GetFontString()
    if fs then
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", 10, 0)
      fs:SetPoint("RIGHT", -24, 0)
      fs:SetJustifyH("LEFT")
      if fs.SetWordWrap then fs:SetWordWrap(false) end
    end
  end
  registry[#registry + 1] = dd
  return dd
end

local function Header(parent, text)
  local fs = Label(parent, text, "GameFontNormal")
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(0.3, 0.55, 1, 0.5)
  line:SetHeight(1)
  line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
  line:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
  return fs
end

local function ItemName(id)
  local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not name and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return name or L.itemFallback:format(id)
end

ns.UI = {
  Label = Label, Button = Button, Check = Check, Edit = Edit, Dropdown = Dropdown,
  Header = Header, FitWidth = FitWidth, ItemName = ItemName,
  SetRegistry = function(t) registry = t or widgets end,
}

------------------------------------------------------------------------
-- window
------------------------------------------------------------------------
local Build

local function Rebuild()
  local point
  if win then
    point = { win:GetPoint() }
    win:Hide()
  end
  win = nil
  wipe(widgets)
  Build()
  if point and point[1] then
    win:ClearAllPoints()
    win:SetPoint(point[1], UIParent, point[3], point[4], point[5])
  end
  win:Show()
  ns.RefreshOptions()
end

Build = function()
  local db = ns.db
  win = CreateFrame("Frame", "FullManaForeverOptions", UIParent)
  win:SetSize(W, 540)
  win:SetPoint("CENTER")
  win:SetFrameStrata("DIALOG")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:SetClampedToScreen(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:Hide()
  if UISpecialFrames then
    local listed = false
    for _, n in ipairs(UISpecialFrames) do if n == "FullManaForeverOptions" then listed = true end end
    if not listed then table.insert(UISpecialFrames, "FullManaForeverOptions") end
  end

  local bg = win:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.06, 0.09, 0.96)
  local top = win:CreateTexture(nil, "ARTWORK")
  top:SetPoint("TOPLEFT")
  top:SetPoint("TOPRIGHT")
  top:SetHeight(2)
  top:SetColorTexture(0.3, 0.55, 1, 0.9)

  local title = Label(win, "Full Mana Forever  |cff888888v" .. ns.VERSION .. "|r", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", PAD, -12)
  local close = Button(win, "X", 22)
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() win:Hide() end)

  -- two columns: display + look on the left, consumables on the right
  local function Column(index)
    local col = CreateFrame("Frame", nil, win)
    col:SetPoint("TOPLEFT", win, "TOPLEFT", (index - 1) * W, 0)
    col:SetSize(W, 10)
    local c = { frame = col, y = -44 }
    function c.Row(frame, x, dy)
      frame:SetPoint("TOPLEFT", col, "TOPLEFT", x or PAD, c.y)
      c.y = c.y - (dy or 26)
    end
    function c.Right(frame)
      frame:SetPoint("TOPRIGHT", col, "TOPRIGHT", -PAD, c.y + 3)
    end
    return c
  end
  local left, right = Column(1), Column(2)
  local sep = win:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(0.3, 0.55, 1, 0.25)
  sep:SetWidth(1)
  sep:SetPoint("TOP", win, "TOPLEFT", W, -44)
  sep:SetPoint("BOTTOM", win, "BOTTOMLEFT", W, 12)

  -- shows/hides rows that only matter while the mana bar is on
  local function BarOnly(...)
    local list = { ... }
    registry[#registry + 1] = { Refresh = function()
      local on = db.showBar and true or false
      for _, f in ipairs(list) do f:SetShown(on) end
    end }
  end

  ------------------------------------------------------------ left column
  local c = left
  local col = c.frame
  c.Row(Header(col, L.optDisplay), PAD, 24)
  c.Row(Check(col, L.optLock, function() return db.locked end, function(v) db.locked = v; ns.ApplyLock() end))
  c.Row(Check(col, L.optTest, function() return db.test end, function(v) db.test = v end))
  c.Row(Check(col, L.optCombat, function() return db.onlyCombat end, function(v) db.onlyCombat = v end))
  c.Row(Label(col, L.optShowIn .. ":"), PAD + 4, 24)
  local x = PAD + 26
  for _, key in ipairs({ "showSolo", "showParty", "showRaid" }) do
    local cb = Check(col, L[key], function() return db[key] end, function(v) db[key] = v end)
    cb:SetPoint("TOPLEFT", col, "TOPLEFT", x, c.y)
    -- next box right after this label (label lengths differ a lot between languages)
    x = x + 28 + math.max(60, math.ceil(cb.label:GetStringWidth() or 80)) + 18
  end
  c.y = c.y - 28
  local langLabel = Label(col, L.optLang .. ":")
  local entries = { { value = "auto", text = L.langAuto .. " (" .. ns.LanguageName(ns.GameLanguage()) .. ")" } }
  for _, l in ipairs(ns.LANGUAGES) do entries[#entries + 1] = { value = l.code, text = l.name } end
  local lang = Dropdown(col, 190, entries, function()
    if db.language == "auto" then return L.langAuto end
    return ns.LanguageName(db.language, true)
  end, function(code)
    db.language = code
    ns.SetLanguage(code)
    ns.OnLanguageChanged()
    if panelButton then panelButton:SetText(L.optOpen); FitWidth(panelButton, 220) end
    Rebuild()
    if ns.RebuildLibrary then ns.RebuildLibrary(true) end
  end)
  c.Right(lang)
  c.Row(langLabel, PAD + 4, 30)
  local reset = Button(col, L.optReset, 150)
  c.Row(reset, PAD + 4, 34)
  reset:SetScript("OnClick", function() ns.ResetPosition() end)

  -- look
  c.Row(Header(col, L.optAppearance), PAD, 26)
  local layLabel = Label(col, L.optLayout .. ":")
  local lay = Dropdown(col, 230, {
    { value = false, text = L.layoutH }, { value = true, text = L.layoutV },
  }, function() return db.vertical and L.layoutV or L.layoutH end,
  function(v) db.vertical = v; ns.Layout(true); Rebuild() end)
  c.Right(lay)
  c.Row(layLabel, PAD + 4, 30)

  local size = Stepper(col, L.optSize .. ":", function() return db.iconSize end,
    function(v) db.iconSize = v; ns.Layout(true) end, 4, 24, 96, function(v) return tostring(v) end)
  c.Row(size.label, PAD + 4, 28)
  local gap = Stepper(col, L.optGap .. ":", function() return db.iconGap end,
    function(v) db.iconGap = v; ns.Layout(true) end, 2, 0, 24, function(v) return tostring(v) end)
  c.Row(gap.label, PAD + 4, 30)

  c.Row(Check(col, L.optBar, function() return db.showBar end, function(v) db.showBar = v end))
  local bpLabel = Label(col, L.optBarPos .. ":")
  local bp
  if db.vertical then
    bp = Dropdown(col, 230, {
      { value = "left", text = L.barLeft }, { value = "right", text = L.barRight },
    }, function() return db.barSide == "right" and L.barRight or L.barLeft end,
    function(v) db.barSide = v; ns.Layout(true); ns.RefreshOptions() end)
  else
    bp = Dropdown(col, 230, {
      { value = "below", text = L.barBelow }, { value = "above", text = L.barAbove },
    }, function() return db.barPosition == "above" and L.barAbove or L.barBelow end,
    function(v) db.barPosition = v; ns.Layout(true); ns.RefreshOptions() end)
  end
  c.Right(bp)
  c.Row(bpLabel, PAD + 30, 30)

  local colorEntries = {}
  for _, bc in ipairs(ns.BAR_COLORS) do
    colorEntries[#colorEntries + 1] = { value = bc.key, text = L["col_" .. bc.key] }
  end
  local colLabel = Label(col, L.optBarColor .. ":")
  local colDD = Dropdown(col, 230, colorEntries, function() return L["col_" .. (db.barColor or "blue")] end,
    function(v) db.barColor = v; ns.Layout(true); ns.RefreshOptions() end)
  c.Right(colDD)
  c.Row(colLabel, PAD + 30, 30)

  local thick = Stepper(col, L.optBarThick .. ":", function() return db.barThickness end,
    function(v) db.barThickness = v; ns.Layout(true) end, 2, 6, 40, function(v) return tostring(v) end)
  thick.label:SetPoint("TOPLEFT", col, "TOPLEFT", PAD + 30, c.y)
  c.y = c.y - 28
  local blen = Stepper(col, L.optBarLen .. ":", function() return db.barLength end,
    function(v) db.barLength = v; ns.Layout(true) end, 20, 0, 800,
    function(v) return v == 0 and L.lenAuto or tostring(v) end)
  blen.label:SetPoint("TOPLEFT", col, "TOPLEFT", PAD + 30, c.y)
  c.y = c.y - 30
  BarOnly(bpLabel, bp, colLabel, colDD, thick.label, thick.value, thick.minus, thick.plus,
    blen.label, blen.value, blen.minus, blen.plus)

  ------------------------------------------------------------ right column
  c = right
  col = c.frame
  c.Row(Header(col, L.optGroups), PAD, 24)

  -- one choice instead of two lists: how eagerly to drink
  local function Strategy()
    if db.pickMode == "strongest" then return "strong" end
    return db.thresholdMode == "avg" and "often" or "safe"
  end
  local stratText = { safe = L.stratSafe, often = L.stratOften, strong = L.stratStrong }
  local stratDesc = { safe = L.stratSafeDesc, often = L.stratOftenDesc, strong = L.stratStrongDesc }
  local stLabel = Label(col, L.optStrategy .. ":")
  local strat = Dropdown(col, 230, {
    { value = "safe", text = L.stratSafe }, { value = "often", text = L.stratOften },
    { value = "strong", text = L.stratStrong },
  }, function() return stratText[Strategy()] end,
  function(v)
    if v == "strong" then db.pickMode, db.thresholdMode = "strongest", "max"
    elseif v == "often" then db.pickMode, db.thresholdMode = "fit", "avg"
    else db.pickMode, db.thresholdMode = "fit", "max" end
    ns.InvalidateCurves(); ns.RefreshOptions()
  end)
  c.Right(strat)
  c.Row(stLabel, PAD + 4, 28)
  local desc = Label(col, "", "GameFontDisableSmall")
  desc:SetWidth(W - 2 * PAD - 8)
  c.Row(desc, PAD + 4, 44)
  registry[#registry + 1] = { Refresh = function() desc:SetText(stratDesc[Strategy()]) end }
  widgets.status = {}
  for i, group in ipairs(ns.GROUPS) do
    if ns.ForMyClass(group) then
      c.Row(Check(col, L["grp_" .. group.key], function() return db.enabled[group.key] end,
        function(v) db.enabled[group.key] = v end), PAD, 20)
      local st = Label(col, "", "GameFontHighlightSmall")
      st:SetWidth(W - 2 * PAD - 30)
      c.Row(st, PAD + 30, 22)
      widgets.status[i] = st
    end
  end
  local margin = Stepper(col, L.optMargin .. ":", function() return db.runeMargin end,
    function(v) db.runeMargin = v; ns.InvalidateCurves() end, 0.05, 0.10, 0.80,
    function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end)
  c.Row(margin.label, PAD + 4, 30)

  c.y = c.y - 6
  local items = Button(col, L.optItems, 180, 24)
  c.Row(items, PAD, 34)
  items:SetScript("OnClick", function() ns.ToggleLibrary(true) end)

  win:SetWidth(2 * W)
  win:SetHeight(math.max(-left.y, -right.y) + 8)

  local acc = 0
  win:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc > 0.5 then acc = 0; ns.RefreshOptions() end
  end)
end

------------------------------------------------------------------------
-- refresh
------------------------------------------------------------------------
function ns.RefreshOptions()
  if not win or not win:IsShown() then return end
  local db = ns.db
  for _, w in ipairs(widgets) do w.Refresh() end

  for i, group in ipairs(ns.GROUPS) do
    if widgets.status[i] then
    local text
    if not db.enabled[group.key] then
      text = "|cff888888" .. L.stDisabled .. "|r"
    else
      local item, n, ready, left, thr, hpThr = ns.GetStatus(i)
      if not item then
        text = "|cff888888" .. L.stNone .. "|r"
      elseif not ready then
        text = "|cffffaa33" .. L.stCooldown:format(ItemName(item.id), n, math.ceil(left)) .. "|r"
      else
        text = "|cff66ff66" .. L.stReady:format(ItemName(item.id), n, math.floor(math.max(thr or 0, 0) * 100))
        if hpThr then
          if hpThr >= 1 then
            text = text .. " |cffff4444" .. L.stHpNever .. "|r"
          else
            text = text .. L.stHp:format(math.ceil(hpThr * 100))
          end
        end
        text = text .. "|r"
      end
    end
    widgets.status[i]:SetText(text)
    end
  end

end

function ns.ToggleOptions(forceShow)
  if not win then Build() end
  if forceShow or not win:IsShown() then
    win:Show()
    ns.RefreshOptions()
  else
    win:Hide()
  end
end

------------------------------------------------------------------------
-- entry in the game's Settings -> AddOns list
------------------------------------------------------------------------
function ns.InitOptions()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local panel = CreateFrame("Frame")
  local t = Label(panel, "Full Mana Forever", "GameFontNormalLarge")
  t:SetPoint("TOPLEFT", 16, -16)
  panelButton = Button(panel, L.optOpen, 220, 26)
  panelButton:SetPoint("TOPLEFT", 16, -50)
  panelButton:SetScript("OnClick", function()
    if SettingsPanel then pcall(HideUIPanel, SettingsPanel) end
    ns.ToggleOptions(true)
  end)
  local category = Settings.RegisterCanvasLayoutCategory(panel, "Full Mana Forever")
  Settings.RegisterAddOnCategory(category)
end
