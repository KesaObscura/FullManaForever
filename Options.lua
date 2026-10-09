-- Full Mana Forever - options window.
-- Built without Blizzard templates on purpose: templates change between client
-- versions, and Forever is a moving target. Everything here is plain frames.

local _, ns = ...
local L = ns.L
local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
local win, panelButton
local widgets = {}        -- options widgets that need Refresh()
local groupRows = {}      -- consumable groups in the window: { cb, st, i, compact, placed }
local groupTail           -- { frame, dx }: what follows the last group (rune margin)
local registry = widgets  -- where the widget helpers register (see WithRegistry)
local openList            -- the dropdown list that is open right now (only one at a time)

local W, PAD = 440, 16
-- fixed columns inside a settings column: every dropdown has the same width and left
-- edge, stepper values start where dropdown texts start, -/+ buttons right after them
local DD_W = 230
local VALUE_X = W - PAD - DD_W + 10
local BTN_X = VALUE_X + 60

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

-- tooltip on hover: title in white, explanation wrapped below
local function Tip(frame, title, text)
  if not text then return end
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(text, 0.82, 0.82, 0.82, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- a mouse area over a text, so the text itself can carry a tooltip
local function TipArea(parent, fs, title, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints(fs)
  f:EnableMouse(true)
  Tip(f, title, text)
  return f
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
  b:SetDisabledFontObject("GameFontDisableSmall")
  b:SetText(text)
  FitWidth(b, w)
  return b
end

local function Check(parent, text, get, set, tip, enabledIf)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetSize(24, 24)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  -- a greyed-out box shows a grey tick, not the bright one
  cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  cb.label = Label(parent, text)
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  -- the label is part of the button: it toggles the box and shows the tooltip
  cb:SetHitRectInsets(0, -math.ceil((cb.label:GetStringWidth() or 0) + 4), 0, 0)
  Tip(cb, text, tip)
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    ns.RefreshOptions()
  end)
  cb.Refresh = function()
    cb:SetChecked(get() and true or false)
    if enabledIf then
      local on = enabledIf() and true or false
      cb:SetEnabled(on)
      cb:SetAlpha(on and 1 or 0.6)
      if on then cb.label:SetTextColor(1, 1, 1) else cb.label:SetTextColor(0.5, 0.5, 0.5) end
    end
  end
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

-- "Label:      value [-] [+]" with the value and the buttons in fixed columns.
-- x = where the label starts (the caller places it there). o: step, lo, hi, fmt, tip,
-- next(v, dir) for steppers that do not simply add a step (bar length).
local function Stepper(parent, x, text, get, set, o)
  local s = { x = x }
  -- "Spells at mana <=" ends in a sign already: no colon after it
  s.label = Label(parent, (text == "" or text:sub(-1) == "=") and text or (text .. ":"))
  s.value = Label(parent, "", "GameFontNormal")
  s.minus = Button(parent, "-", 22)
  s.plus = Button(parent, "+", 22)
  s.value:SetPoint("LEFT", s.label, "LEFT", VALUE_X - x, 0)
  s.minus:SetPoint("LEFT", s.label, "LEFT", BTN_X - x, 0)
  s.plus:SetPoint("LEFT", s.minus, "RIGHT", 4, 0)
  if o.tip then TipArea(parent, s.label, text, o.tip) end
  local function step(v, dir)
    if o.next then return o.next(v, dir) end
    return tonumber(("%.2f"):format(math.min(o.hi, math.max(o.lo, v + dir * o.step))))
  end
  local function change(dir)
    local v = get()
    local nv = step(v, dir)
    if nv ~= v then set(nv) end
    ns.RefreshOptions()
  end
  s.minus:SetScript("OnClick", function() change(-1) end)
  s.plus:SetScript("OnClick", function() change(1) end)
  s.Refresh = function()
    local v = get()
    s.value:SetText(o.fmt(v))
    -- a button that would not change anything is greyed out
    for _, b in ipairs({ { s.minus, -1 }, { s.plus, 1 } }) do
      local on = step(v, b[2]) ~= v
      b[1]:SetEnabled(on)
      b[1]:SetAlpha(on and 1 or 0.3) -- a grey "-" alone is too small to notice
    end
  end
  registry[#registry + 1] = s
  return s
end

-- Blizzard-style dropdown: a button that opens a list below it.
-- dd.Select(value) is what a click on a list row does (also used by the tests).
local function Dropdown(parent, width, entries, getText, onPick)
  local dd = Button(parent, " ", width)
  dd:SetWidth(width)
  dd.entries = entries
  local fs = dd:GetFontString()
  if fs then
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", 10, 0)
    fs:SetPoint("RIGHT", -24, 0)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
  end
  local arrow = dd:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", -6, 0)
  arrow:SetRotation(-math.pi / 2)

  local list = CreateFrame("Frame", nil, dd)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", 0, -2)
  list:SetClampedToScreen(true) -- near the bottom of the screen the list moves up
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

  function dd.Select(value)
    list:Hide()
    onPick(value)
  end

  local rows, maxW = {}, width
  for i, e in ipairs(entries) do
    local r = Button(list, e.text, width, 20)
    local rfs = r:GetFontString()
    if rfs then
      rfs:ClearAllPoints()
      rfs:SetPoint("LEFT", 10, 0)
    end
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -2 - (i - 1) * 21)
    r:SetScript("OnClick", function() dd.Select(e.value) end)
    maxW = math.max(maxW, r:GetWidth())
    rows[i] = r
  end
  for _, r in ipairs(rows) do r:SetWidth(maxW) end
  list:SetSize(maxW + 4, #entries * 21 + 3)

  dd:SetScript("OnClick", function()
    if list:IsShown() then list:Hide() return end
    if openList and openList ~= list then openList:Hide() end
    openList = list
    list:Show()
  end)
  dd:SetScript("OnHide", function() list:Hide() end)
  dd.Refresh = function()
    local text = getText()
    if text ~= dd.text then
      dd.text = text
      dd:SetText(text)
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

-- runs fn with the widget helpers registering into t; the options registry is restored
-- even if fn fails, so one bad build cannot break the options window
local function WithRegistry(t, fn)
  local prev = registry
  registry = t
  local ok, err = pcall(fn)
  registry = prev
  if not ok then error(err, 0) end
end

ns.UI = {
  Label = Label, Button = Button, Check = Check, Edit = Edit, Dropdown = Dropdown,
  ItemName = ItemName, WithRegistry = WithRegistry,
}

------------------------------------------------------------------------
-- window
------------------------------------------------------------------------
local Build

-- A group with a status to show ("Major Mana Potion x5: ...") takes two lines; one with
-- nothing in the bags (or switched off) keeps the short status next to its name.
-- Each row hangs on the one above, so only the anchors change, never the frames.
local GROUP_FULL, GROUP_COMPACT = 42, 26
local function PlaceGroups(force)
  local changed = force
  for _, r in ipairs(groupRows) do
    if r.placed ~= (r.compact or false) then changed = true end
  end
  if not changed then return end
  for k, r in ipairs(groupRows) do
    r.placed = r.compact or false
    r.st:ClearAllPoints()
    if r.compact then
      r.st:SetPoint("LEFT", r.cb.label, "RIGHT", 8, 0)
      r.st:SetWidth(math.max(40, W - 2 * PAD - 36 - math.ceil(r.cb.label:GetStringWidth() or 0)))
    else
      r.st:SetPoint("TOPLEFT", r.cb, "TOPLEFT", 30, -20)
      r.st:SetWidth(W - 2 * PAD - 30)
    end
    local nextRow = groupRows[k + 1]
    local f, dx = nextRow and nextRow.cb, 0
    if not nextRow and groupTail then f, dx = groupTail.frame, groupTail.dx end
    if f then
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", r.cb, "TOPLEFT", dx, -(r.compact and GROUP_COMPACT or GROUP_FULL))
    end
  end
end

local function Rebuild()
  local point
  if win then
    point = { win:GetPoint() }
    win:Hide()
  end
  win = nil
  wipe(widgets)
  wipe(groupRows)
  groupTail = nil
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
  win:SetPoint("CENTER")          -- size is set at the end, from the two columns
  win:SetFrameStrata("DIALOG")
  win:SetToplevel(true)
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
  bg:SetColorTexture(0.05, 0.06, 0.09, 1)
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

  -- settings that only matter while a switch is on stay in place but are greyed out and
  -- cannot be used while it is off. Registered after the widgets, so this runs after their
  -- own Refresh (a stepper greys its own buttons at the limits).
  local function ActiveIf(cond, ...)
    local list = { ... }
    registry[#registry + 1] = { Refresh = function()
      local on = cond() and true or false
      for _, w in ipairs(list) do
        if w.minus then -- stepper: label, value and both buttons
          w.label:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
          w.value:SetTextColor(on and 1 or 0.5, on and 0.82 or 0.5, on and 0 or 0.5)
          if not on then
            for _, b in ipairs({ w.minus, w.plus }) do b:SetEnabled(false); b:SetAlpha(0.3) end
          end
        elseif w.SetEnabled then -- dropdown or button
          w:SetEnabled(on)
          w:SetAlpha(on and 1 or 0.5)
        else -- a label
          w:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
        end
      end
    end }
  end

  ------------------------------------------------------------ left column
  local c = left
  local col = c.frame
  c.Row(Header(col, L.optDisplay), PAD, 24)
  -- one switch for placing: unlocked = movable and showing everything that is switched on
  -- two equal halves: unlock and "Move texts freely" side by side, the two reset buttons
  -- below them, together as wide as the column
  local HALF = math.floor((W - 2 * PAD - 8) / 2)
  local X2 = PAD + HALF + 8
  local unlockCb = Check(col, L.optUnlock, function() return not db.locked end,
    function(v) db.locked = not v; ns.ApplyLock() end, L.tipUnlock)
  c.Row(unlockCb)
  -- mana numbers, rule seconds and regen: each can be dragged on its own, only while unlocked
  local freeCb = Check(col, L.optTextFree, function() return db.textFree end,
    function(v) db.textFree = v; ns.PositionBar(); ns.ApplyLock() end, L.tipTextFree,
    function() return not db.locked end)
  -- a long "Unlock frame" label (some languages) would run into it: then it goes one row down
  if PAD + 28 + math.ceil(unlockCb.label:GetStringWidth() or 0) + 8 <= X2 then
    freeCb:SetPoint("TOPLEFT", col, "TOPLEFT", X2, c.y + 26)
  else
    c.Row(freeCb)
  end
  -- placing the frame: unlock, then reset if it got lost; sizes back to the defaults
  local reset = Button(col, L.optReset, HALF)
  reset:SetWidth(HALF)
  c.Row(reset, PAD, 34)
  reset:SetScript("OnClick", function() ns.ResetPosition() end)
  Tip(reset, L.optReset, L.tipReset)
  local resetSize = Button(col, L.optResetSize, HALF)
  resetSize:SetWidth(HALF)
  resetSize:SetPoint("TOPLEFT", col, "TOPLEFT", X2, c.y + 34)
  resetSize:SetScript("OnClick", function() ns.ResetSize(); ns.RefreshOptions() end)
  Tip(resetSize, L.optResetSize, L.tipResetSize)
  local langLabel = Label(col, L.optLang .. ":")
  local entries = { { value = "auto", text = L.langAuto .. " (" .. ns.LanguageName(ns.GameLanguage()) .. ")" } }
  for _, l in ipairs(ns.LANGUAGES) do entries[#entries + 1] = { value = l.code, text = l.name } end
  local lang = Dropdown(col, DD_W, entries, function()
    if db.language == "auto" then return L.langAuto end
    return ns.LanguageName(db.language, true)
  end, function(code)
    if code == db.language then return end -- rebuilding creates new frames: only on a change
    db.language = code
    ns.SetLanguage(code)
    ns.OnLanguageChanged()
    if panelButton then panelButton:SetText(L.optOpen); FitWidth(panelButton, 220) end
    Rebuild()
    if ns.RebuildLibrary then ns.RebuildLibrary(true) end
  end)
  c.Right(lang)
  c.Row(langLabel, PAD + 4, 34)

  -- look
  c.Row(Header(col, L.optAppearance), PAD, 26)
  local layLabel = Label(col, L.optLayout .. ":")
  local lay = Dropdown(col, DD_W, {
    { value = false, text = L.layoutH }, { value = true, text = L.layoutV },
  }, function() return db.vertical and L.layoutV or L.layoutH end,
  function(v)
    if v == db.vertical then return end
    db.vertical = v; ns.Layout(true); Rebuild()
  end)
  c.Right(lay)
  c.Row(layLabel, PAD + 4, 30)

  local function num(v) return tostring(v) end
  local size = Stepper(col, PAD + 4, L.optSize, function() return db.iconSize end,
    function(v) db.iconSize = v; ns.Layout(true) end, { step = 4, lo = 24, hi = 96, fmt = num })
  c.Row(size.label, PAD + 4, 28)
  local gap = Stepper(col, PAD + 4, L.optGap, function() return db.iconGap end,
    function(v) db.iconGap = v; ns.Layout(true) end, { step = 2, lo = 0, hi = 24, fmt = num })
  c.Row(gap.label, PAD + 4, 30)

  c.Row(Check(col, L.optBar, function() return db.showBar end, function(v) db.showBar = v end, L.tipBar))
  local bpLabel = Label(col, L.optBarPos .. ":")
  local bp
  if db.vertical then
    bp = Dropdown(col, DD_W, {
      { value = "left", text = L.barLeft }, { value = "right", text = L.barRight },
    }, function() return db.barSide == "right" and L.barRight or L.barLeft end,
    function(v) db.barSide = v; ns.Layout(true); ns.RefreshOptions() end)
  else
    bp = Dropdown(col, DD_W, {
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
  local colDD = Dropdown(col, DD_W, colorEntries, function() return L["col_" .. (db.barColor or "blue")] or L.col_blue end,
    function(v) db.barColor = v; ns.Layout(true); ns.RefreshOptions() end)
  c.Right(colDD)
  c.Row(colLabel, PAD + 30, 30)


  local thick = Stepper(col, PAD + 30, L.optBarThick, function() return db.barThickness end,
    function(v) db.barThickness = v; ns.Layout(true) end, { step = 2, lo = 6, hi = 40, fmt = num })
  c.Row(thick.label, PAD + 30, 28)
  -- length: 0 = auto. Leaving auto starts at the auto length; going below one icon
  -- (a bar shorter than an icon is useless) returns to auto.
  local LEN_STEP, LEN_MAX = 20, 800
  local blen = Stepper(col, PAD + 30, L.optBarLen, function() return db.barLength end,
    function(v) db.barLength = v; ns.Layout(true) end, {
      fmt = function(v) return v == 0 and L.lenAuto or tostring(v) end,
      tip = L.tipBarLen,
      next = function(v, dir)
        if v == 0 then
          if dir < 0 then return 0 end
          return math.min(LEN_MAX, math.ceil(ns.AutoBarLength() / LEN_STEP) * LEN_STEP)
        end
        local nv = math.min(LEN_MAX, v + dir * LEN_STEP)
        if nv >= db.iconSize then return nv end
        if dir < 0 then return 0 end
        -- "+" never jumps to auto: it grows to the first step that is not below one icon
        return math.min(LEN_MAX, math.ceil(db.iconSize / LEN_STEP) * LEN_STEP)
      end,
    })
  c.Row(blen.label, PAD + 30, 32)
  -- the bar's own look only matters while it is on
  ActiveIf(function() return db.showBar end, bpLabel, bp, colLabel, colDD, thick, blen)
  -- the three texts: each has its own switch and text size and also shows without the bar
  -- (the size on its own row below: long names would run into the value)
  local function pct(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
  local function SizeStepper(key)
    local st = Stepper(col, PAD + 30, L.optTextSize, function() return db[key] or 1 end,
      function(v) db[key] = v; ns.Layout(true) end, { step = 0.1, lo = 0.6, hi = 2.0, fmt = pct })
    c.Row(st.label, PAD + 30, 28)
    return st
  end
  -- mana numbers like the game's "Status Text": number, percentage or both
  local mtText = { number = L.mtNumber, percent = L.mtPercent, both = L.mtBoth }
  local manaCb = Check(col, L.optManaText, function() return db.manaTextOn end,
    function(v) db.manaTextOn = v end, L.tipManaText)
  local mtDD = Dropdown(col, DD_W, {
    { value = "number", text = L.mtNumber }, { value = "percent", text = L.mtPercent },
    { value = "both", text = L.mtBoth },
  }, function() return mtText[db.manaText or "number"] or L.mtNumber end,
  function(v) db.manaText = v; ns.RefreshOptions() end)
  c.Right(mtDD)
  c.Row(manaCb, PAD, 30)
  ActiveIf(function() return db.manaTextOn end, mtDD, SizeStepper("manaScale"))
  c.Row(Check(col, L.optFsr, function() return db.fsr end,
    function(v) db.fsr = v; ns.Layout(true) end, L.tipFsr), PAD, 26)
  ActiveIf(function() return db.fsr end, SizeStepper("fsrScale"))
  c.Row(Check(col, L.optRegen, function() return db.regenText end,
    function(v) db.regenText = v end, L.tipRegen), PAD, 26)
  ActiveIf(function() return db.regenText end, SizeStepper("regenScale"))

  ------------------------------------------------------------ right column
  c = right
  col = c.frame
  -- when the icons are shown at all
  c.Row(Header(col, L.optVisibility), PAD, 24)
  c.Row(Check(col, L.optCombat, function() return db.onlyCombat end, function(v) db.onlyCombat = v end,
    L.tipCombat))
  local showLabel = Label(col, L.optShowIn .. ":")
  c.Row(showLabel, PAD + 4, 24)
  TipArea(col, showLabel, L.optShowIn, L.tipShowIn)
  local x = PAD + 26
  for _, key in ipairs({ "showSolo", "showParty", "showRaid" }) do
    local cb = Check(col, L[key], function() return db[key] end, function(v) db[key] = v end, L.tipShowIn)
    cb:SetPoint("TOPLEFT", col, "TOPLEFT", x, c.y)
    -- next box right after this label (label lengths differ a lot between languages)
    x = x + 28 + math.max(60, math.ceil(cb.label:GetStringWidth() or 80)) + 18
  end
  c.y = c.y - 34

  c.Row(Header(col, L.optGroups), PAD, 24)
  -- one choice instead of two lists: how eagerly to drink
  local function Strategy()
    if db.pickMode == "strongest" then return "strong" end
    return db.thresholdMode == "avg" and "often" or "safe"
  end
  local stratText = { safe = L.stratSafe, often = L.stratOften, strong = L.stratStrong }
  local stratDesc = { safe = L.stratSafeDesc, often = L.stratOftenDesc, strong = L.stratStrongDesc }
  local stLabel = Label(col, L.optStrategy .. ":")
  local strat = Dropdown(col, DD_W, {
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
  local desc = Label(col, "", "GameFontHighlightSmall")
  desc:SetTextColor(0.74, 0.78, 0.88)
  desc:SetWidth(W - 2 * PAD - 8)
  c.Row(desc, PAD + 4, 44)
  registry[#registry + 1] = { Refresh = function() desc:SetText(stratDesc[Strategy()]) end }

  -- groups are chained: a group with nothing to report keeps its status on the same
  -- line and takes less room (see PlaceGroups); the first one sits at a fixed spot
  local first = true
  for i, group in ipairs(ns.GROUPS) do
    if ns.ForMyClass(group) then
      local cb = Check(col, L["grp_" .. group.key], function() return db.enabled[group.key] end,
        function(v) db.enabled[group.key] = v; ns.Layout(true) end, -- auto bar length follows
        L["tipGrp_" .. group.key])
      if first then cb:SetPoint("TOPLEFT", col, "TOPLEFT", PAD, c.y); first = false end
      local st = Label(col, "", "GameFontHighlightSmall")
      if st.SetWordWrap then st:SetWordWrap(false) end -- one line; long texts end in "..."
      groupRows[#groupRows + 1] = { cb = cb, st = st, i = i }
      c.y = c.y - GROUP_FULL -- room for the worst case: every group with a status line
    end
  end
  local margin = Stepper(col, PAD + 4, L.optMargin, function() return db.runeMargin end,
    function(v) db.runeMargin = v; ns.InvalidateCurves() end,
    { step = 0.05, lo = 0.10, hi = 0.80, tip = L.tipMargin,
      fmt = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end })
  groupTail = { frame = margin.label, dx = 4 }
  if #groupRows == 0 then margin.label:SetPoint("TOPLEFT", col, "TOPLEFT", PAD + 4, c.y) end
  c.y = c.y - 36
  -- own spells (Evocation, Innervate, ...): one mana% for all of them
  local spellThr = Stepper(col, PAD + 4, L.optSpellThr, function() return db.spellThreshold end,
    function(v) db.spellThreshold = v; ns.InvalidateCurves() end,
    { step = 0.05, lo = 0.10, hi = 0.90, tip = L.tipSpellThr,
      fmt = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end })
  spellThr.label:SetPoint("TOPLEFT", margin.label, "TOPLEFT", 0, -32)
  c.y = c.y - 32
  ActiveIf(function() return db.enabled.rune end, margin)
  ActiveIf(function() return db.enabled.spell end, spellThr)
  local items = Button(col, L.optItems, 180, 24)
  items:SetPoint("TOPLEFT", spellThr.label, "TOPLEFT", -4, -36)
  items:SetScript("OnClick", function() ns.ToggleLibrary(true) end)
  Tip(items, L.optItems, L.tipItems)
  c.y = c.y - 34
  PlaceGroups(true)

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
-- text, compact (nothing to report: fits next to the group name)
-- own spells: the one that would light up, or the first one and its cooldown
local function SpellStatus()
  local S = ns.Spells
  if not S.FirstKnown() then return "|cff888888" .. L.stSpellNone .. "|r", true end
  local maxMana = UnitPowerMax("player", 0)
  if IsSecret(maxMana) or not maxMana or maxMana <= 0 then maxMana = nil end
  local sp, id = S.Candidate()
  if sp then
    local text = "|cff66ff66" .. L.stSpellReady:format(S.Name(id) or "?",
      math.floor(S.Threshold(sp, maxMana) * 100 + 0.5))
    local hp = S.HpCost(sp)
    local maxHP = UnitHealthMax("player")
    if hp and not IsSecret(maxHP) and maxHP and maxHP > 0 then
      local t = hp / maxHP + ns.db.runeMargin
      text = text .. (t >= 1 and (" |cffff4444" .. L.stHpNever .. "|r") or L.stHp:format(math.ceil(t * 100)))
    end
    return text .. "|r"
  end
  -- none ready: the one that comes back first (unknown wait: Inner Focus, or not read yet)
  local soon, soonID, left = S.Soonest()
  if not left then return "|cffffaa33" .. L.stSpellWait:format(S.Name(soonID) or "?") .. "|r" end
  return "|cffffaa33" .. L.stSpellCd:format(S.Name(soonID) or "?", math.ceil(left)) .. "|r"
end

local function StatusText(i, group)
  local db = ns.db
  if not db.enabled[group.key] then return "|cff888888" .. L.stDisabled .. "|r", true end
  if group.spells then return SpellStatus() end
  if group.key == "potion" and ns.IsHeld and ns.IsHeld() then
    return "|cffffaa33" .. L.stHold .. "|r", true
  end
  local item, n, ready, left, thr, hpThr = ns.GetStatus(i)
  if not item then return "|cff888888" .. (group.equipped and L.stNoneGear or L.stNone) .. "|r", true end
  if not ready then
    return "|cffffaa33" .. L.stCooldown:format(ItemName(item.id), n, math.ceil(left)) .. "|r"
  end
  local text = "|cff66ff66" .. L.stReady:format(ItemName(item.id), n, math.floor(math.max(thr or 0, 0) * 100))
  if hpThr then
    if hpThr >= 1 then
      text = text .. " |cffff4444" .. L.stHpNever .. "|r"
    else
      text = text .. L.stHp:format(math.ceil(hpThr * 100))
    end
  end
  return text .. "|r"
end

function ns.RefreshOptions()
  if not win or not win:IsShown() then return end
  for _, w in ipairs(widgets) do w.Refresh() end
  for _, r in ipairs(groupRows) do
    local text, compact = StatusText(r.i, ns.GROUPS[r.i])
    if text ~= r.st.text then r.st.text = text; r.st:SetText(text) end
    r.compact = compact or false
  end
  PlaceGroups()
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
    -- closing Blizzard's panel from addon code is only safe out of combat
    if SettingsPanel and not InCombatLockdown() then pcall(HideUIPanel, SettingsPanel) end
    ns.ToggleOptions(true)
  end)
  local category = Settings.RegisterCanvasLayoutCategory(panel, "Full Mana Forever")
  Settings.RegisterAddOnCategory(category)
end
