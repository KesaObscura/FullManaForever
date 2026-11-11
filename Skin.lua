-- Full Mana Forever - the look of the windows, in the style of Forever's own windows (0.9.11).
-- One file for the whole series: it only draws, it holds no settings. Every piece uses the
-- client's own textures when the client has them and falls back to plain colours otherwise,
-- so a missing texture never leaves an empty hole.

local _, ns = ...
local Skin = {}
ns.Skin = Skin

Skin.ACCENT = { 0.30, 0.55, 1.00 }      -- this addon's colour: line under the title, HUD
Skin.GOLD = { 1.00, 0.82, 0.00 }        -- labels, like the game's settings
Skin.WHITE = { 0.92, 0.92, 0.92 }       -- values
Skin.GREY = { 0.50, 0.50, 0.50 }        -- greyed out
Skin.BG = { 0.065, 0.06, 0.055 }        -- window background, warm dark like the game's windows
Skin.EDGE = { 0.42, 0.35, 0.22 }        -- thin bronze edges (fields, lists, fallback frame)

local function Has(atlas)
  local get = C_Texture and C_Texture.GetAtlasInfo
  if not get then return false end
  local ok, info = pcall(get, atlas)
  return ok and type(info) == "table"
end
Skin.Has = Has

-- puts an atlas on a texture; false (and nothing changed) when the client lacks it
function Skin.Atlas(tex, atlas)
  if not tex or not tex.SetAtlas or not Has(atlas) then return false end
  return (pcall(tex.SetAtlas, tex, atlas))
end

-- a 1 px frame of four textures around f
function Skin.Edge(f, c, a, layer)
  c = c or Skin.EDGE
  local out = {}
  for _, s in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                       { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local t = f:CreateTexture(nil, layer or "BORDER")
    t:SetPoint(s[1])
    t:SetPoint(s[2])
    if s[3] then t:SetHeight(1) else t:SetWidth(1) end
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    out[#out + 1] = t
  end
  return out
end

-- the metal frame of the game's windows: drawn by hand from the game's corners and edges,
-- else the game's nine-slice layout, else a bronze line
local CORNER = 0.42 -- the metal corners are 95 px in the atlas: scaled to about 40 px
local function MetalByHand(f)
  if not (Has("UI-Frame-Metal-CornerTopLeft") and Has("_UI-Frame-Metal-EdgeTop")) then return false end
  local holder = CreateFrame("Frame", nil, f)
  holder:SetAllPoints()
  holder:SetFrameLevel((f:GetFrameLevel() or 1) + 40)
  local c = math.floor(95 * CORNER + 0.5)
  local cb = math.floor(100 * CORNER + 0.5)
  local o = 6 -- the metal sits a little outside the window
  local function T(atlas, w, h)
    local t = holder:CreateTexture(nil, "OVERLAY")
    Skin.Atlas(t, atlas)
    if w then t:SetWidth(w) end
    if h then t:SetHeight(h) end
    return t
  end
  -- the thick top of the metal is the title band: it sits above the window, so nothing inside
  -- the window moves (owner's test 11 Nov: inside it covered the title and the top row)
  local up = c + 2
  local tl = T("UI-Frame-Metal-CornerTopLeft", c, c); tl:SetPoint("TOPLEFT", -o, up)
  local tr = T("UI-Frame-Metal-CornerTopRight", c, c); tr:SetPoint("TOPRIGHT", o, up)
  local bl = T("UI-Frame-Metal-CornerBottomLeft", c, cb); bl:SetPoint("BOTTOMLEFT", -o, -o)
  local br = T("UI-Frame-Metal-CornerBottomRight", c, cb); br:SetPoint("BOTTOMRIGHT", o, -o)
  local top = T("_UI-Frame-Metal-EdgeTop", nil, c)
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("TOPRIGHT", tr, "TOPLEFT")
  local bottom = T("_UI-Frame-Metal-EdgeBottom", nil, cb)
  bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local left = T("!UI-Frame-Metal-EdgeLeft", c, nil)
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
  local right = T("!UI-Frame-Metal-EdgeRight", c, nil)
  right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  for _, t in ipairs({ top, bottom }) do if t.SetHorizTile then t:SetHorizTile(true) end end
  for _, t in ipairs({ left, right }) do if t.SetVertTile then t:SetVertTile(true) end end
  f.skinMetal = holder
  f.skinBand = up
  return true
end
local function MetalNineSlice(f)
  if not (NineSliceUtil and NineSliceUtil.ApplyLayoutByName) then return false end
  local ok = pcall(function()
    local n = CreateFrame("Frame", nil, f, "NineSlicePanelTemplate")
    n:SetAllPoints()
    n:SetFrameLevel((f:GetFrameLevel() or 1) + 40)
    NineSliceUtil.ApplyLayoutByName(n, "ButtonFrameTemplateNoPortrait")
    f.skinMetal = n
    f.skinBand = 0
  end)
  return ok
end

-- a window: background, metal frame, a thin line in the addon's colour under the title band
-- (titleH = height of the band; 0 = none)
function Skin.Window(f, titleH)
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetAllPoints()
  bg:SetColorTexture(Skin.BG[1], Skin.BG[2], Skin.BG[3], 0.98)
  f.skinBg = bg
  -- by hand first: the game's own nine-slice layout puts the thick band inside the window,
  -- over the title and the top row (owner's test 11 Nov); by hand it sits above the window
  if not MetalByHand(f) and not MetalNineSlice(f) then
    Skin.Edge(f, Skin.EDGE, 1, "ARTWORK")
  end
  if titleH and titleH > 0 then
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 12, -titleH)
    line:SetPoint("TOPRIGHT", -12, -titleH)
    line:SetHeight(1)
    local a = Skin.ACCENT
    line:SetColorTexture(a[1], a[2], a[3], 0.7)
    f.skinTitleLine = line
  end
  return f
end

-- the window title: centred in the metal band above the window, else at the top left inside
function Skin.PlaceTitle(fs, f, pad)
  fs:ClearAllPoints()
  if (f.skinBand or 0) > 0 then
    fs:SetPoint("CENTER", f, "TOP", 0, f.skinBand / 2 - 1)
  else
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", pad or 16, -12)
  end
end
-- the close button: in the right end of the band, else at the top right inside
function Skin.PlaceClose(b, f)
  b:ClearAllPoints()
  if (f.skinBand or 0) > 0 then
    b:SetPoint("CENTER", f, "TOPRIGHT", -14, f.skinBand / 2 - 1)
  else
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
  end
end

-- the red close button of the game's windows; nil when the client lacks it
function Skin.Close(parent)
  if not Has("RedButton-Exit") then return nil end
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(24, 24)
  local n = b:CreateTexture(nil, "ARTWORK")
  n:SetAllPoints()
  Skin.Atlas(n, "RedButton-Exit")
  local p = b:CreateTexture(nil, "ARTWORK")
  p:SetAllPoints()
  if not Skin.Atlas(p, "RedButton-Exit-Pressed") then Skin.Atlas(p, "RedButton-Exit") end
  p:Hide()
  local h = b:CreateTexture(nil, "HIGHLIGHT")
  h:SetAllPoints()
  Skin.Atlas(h, "RedButton-Exit")
  if h.SetBlendMode then h:SetBlendMode("ADD") end
  h:SetAlpha(0.35)
  b:SetScript("OnMouseDown", function() n:Hide(); p:Show() end)
  b:SetScript("OnMouseUp", function() p:Hide(); n:Show() end)
  return b
end

-- the red button of the game's dialogs, in three parts so it stretches to any width
local PANEL = "Interface\\Buttons\\UI-Panel-Button-"
local SLICES = { { 0, 0.09375, 12 }, { 0.09375, 0.53125 }, { 0.53125, 0.625, 12 } }
function Skin.RedButton(b)
  local parts = {}
  for i, s in ipairs(SLICES) do
    local t = b:CreateTexture(nil, "BACKGROUND")
    t:SetTexCoord(s[1], s[2], 0, 0.6875)
    if s[3] then t:SetWidth(s[3]) end
    t:SetPoint("TOP"); t:SetPoint("BOTTOM")
    parts[i] = t
  end
  parts[1]:SetPoint("LEFT")
  parts[3]:SetPoint("RIGHT")
  parts[2]:SetPoint("LEFT", parts[1], "RIGHT")
  parts[2]:SetPoint("RIGHT", parts[3], "LEFT")
  local function state(name)
    for _, t in ipairs(parts) do t:SetTexture(PANEL .. name) end
  end
  state("Up")
  local h = b:CreateTexture(nil, "HIGHLIGHT")
  h:SetAllPoints()
  h:SetTexture(PANEL .. "Highlight")
  h:SetTexCoord(0, 0.625, 0, 0.6875)
  if h.SetBlendMode then h:SetBlendMode("ADD") end
  b:HookScript("OnMouseDown", function(self) if self:IsEnabled() then state("Down") end end)
  b:HookScript("OnMouseUp", function(self) if self:IsEnabled() then state("Up") end end)
  b:HookScript("OnEnable", function() state("Up") end)
  b:HookScript("OnDisable", function() state("Disabled") end)
  b.skinParts = parts
  return b
end

-- a modern check box; false when the client lacks the textures (the caller keeps its own)
function Skin.Check(cb)
  if not (Has("checkbox-minimal") and Has("checkmark-minimal")) then return false end
  if not (cb.SetNormalAtlas and cb.SetCheckedAtlas) then return false end
  local ok = pcall(function()
    cb:SetNormalAtlas("checkbox-minimal")
    cb:SetPushedAtlas("checkbox-minimal")
    cb:SetCheckedAtlas("checkmark-minimal")
    if Has("checkmark-minimal-disabled") then cb:SetDisabledCheckedAtlas("checkmark-minimal-disabled") end
    cb:SetHighlightAtlas("checkbox-minimal", "ADD")
    local h = cb:GetHighlightTexture()
    if h then h:SetAlpha(0.3) end
  end)
  return ok
end

-- a dark field with a bronze edge (dropdowns, typed numbers)
function Skin.Field(f, layer)
  local bg = f:CreateTexture(nil, layer or "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.03, 0.03, 0.03, 0.9)
  Skin.Edge(f, Skin.EDGE, 0.9)
  return bg
end

-- the arrow button of the game's dropdowns on the right of a dropdown; nil without it
function Skin.DropArrow(dd)
  if not Has("common-dropdown-a-button") then return nil end
  local t = dd:CreateTexture(nil, "ARTWORK")
  t:SetSize(22, 22)
  t:SetPoint("RIGHT", -1, 0)
  Skin.Atlas(t, "common-dropdown-a-button")
  dd:HookScript("OnEnter", function(self)
    if self:IsEnabled() then Skin.Atlas(t, "common-dropdown-a-button-hover") end
  end)
  dd:HookScript("OnLeave", function(self)
    if self:IsEnabled() then Skin.Atlas(t, "common-dropdown-a-button") end
  end)
  dd:HookScript("OnDisable", function() Skin.Atlas(t, "common-dropdown-a-button-disabled") end)
  dd:HookScript("OnEnable", function() Skin.Atlas(t, "common-dropdown-a-button") end)
  return t
end

-- a small square button with an arrow (◄ ►) for steppers; false without the textures
function Skin.Arrow(b, dir)
  if not (Has("common-button-square-gray-up") and Has("common-dropdown-icon-next")) then return false end
  local n = b:CreateTexture(nil, "BACKGROUND")
  n:SetAllPoints()
  Skin.Atlas(n, "common-button-square-gray-up")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(14, 14)
  icon:SetPoint("CENTER")
  Skin.Atlas(icon, dir < 0 and "common-dropdown-icon-back" or "common-dropdown-icon-next")
  local h = b:CreateTexture(nil, "HIGHLIGHT")
  h:SetAllPoints()
  Skin.Atlas(h, "common-button-square-gray-up")
  if h.SetBlendMode then h:SetBlendMode("ADD") end
  h:SetAlpha(0.25)
  b:HookScript("OnMouseDown", function(self)
    if self:IsEnabled() and Has("common-button-square-gray-down") then Skin.Atlas(n, "common-button-square-gray-down") end
  end)
  b:HookScript("OnMouseUp", function() Skin.Atlas(n, "common-button-square-gray-up") end)
  b:HookScript("OnDisable", function() if icon.SetDesaturated then icon:SetDesaturated(true) end end)
  b:HookScript("OnEnable", function() if icon.SetDesaturated then icon:SetDesaturated(false) end end)
  b.skinIcon = icon
  return true
end

-- the divider line under a section header
function Skin.Divider(parent)
  local t = parent:CreateTexture(nil, "ARTWORK")
  if Skin.Atlas(t, "Options_HorizontalDivider") then
    t:SetHeight(1)
  else
    t:SetHeight(1)
    local e = Skin.EDGE
    t:SetColorTexture(e[1], e[2], e[3], 0.8)
  end
  return t
end
