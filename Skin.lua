-- Full Mana Forever - the look of the windows, in the style of Forever's own windows (0.9.11).
-- One file for the whole series: it only draws, it holds no settings. Every piece uses the
-- client's own textures when the client has them and falls back to plain colours otherwise,
-- so a missing texture never leaves an empty hole.

local _, ns = ...
local Skin = {}
ns.Skin = Skin

Skin.ACCENT = { 0.30, 0.55, 1.00 }      -- this addon's colour: line under the title, HUD
Skin.LOGO = "Interface\\AddOns\\FullManaForever\\icon" -- this addon's logo in the round corner
Skin.GOLD = { 1.00, 0.82, 0.00 }        -- labels, like the game's settings
Skin.WHITE = { 0.92, 0.92, 0.92 }       -- values
Skin.GREY = { 0.50, 0.50, 0.50 }        -- greyed out
Skin.BG = { 0.065, 0.06, 0.055 }        -- window background, warm dark like the game's windows
Skin.EDGE = { 0.42, 0.35, 0.22 }        -- thin bronze edges (fields, lists, fallback frame)

-- whether the client has an atlas; asked once per name (the answer never changes in a session)
local known = {}
local function Has(atlas)
  local k = known[atlas]
  if k ~= nil then return k end
  local get = C_Texture and C_Texture.GetAtlasInfo
  if not get then return false end -- not cached: the tests switch the API on and off
  local ok, info = pcall(get, atlas)
  k = ok and type(info) == "table"
  known[atlas] = k
  return k
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

-- the game's own frame of its windows (the same as the profession or spell book windows), with
-- the round portrait at the top left when one is given. Its title band lies inside the window
-- (f.skinTop = its height): the window moves its content below it.
Skin.TOP = 24
local function MetalNineSlice(f, portrait)
  if not (NineSliceUtil and NineSliceUtil.ApplyLayoutByName) then return false end
  local ok = pcall(function()
    local n = CreateFrame("Frame", nil, f, "NineSlicePanelTemplate")
    n:SetAllPoints()
    n:SetFrameLevel((f:GetFrameLevel() or 1) + 40)
    NineSliceUtil.ApplyLayoutByName(n, portrait and "PortraitFrameTemplate" or "ButtonFrameTemplateNoPortrait")
    f.skinMetal = n
  end)
  if not ok then return false end
  f.skinTop = Skin.TOP
  if portrait then
    -- the logo in the round hole of the metal corner (below the metal, like the game's portraits)
    local p = f:CreateTexture(nil, "OVERLAY")
    p:SetSize(58, 58)
    p:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 6)
    p:SetTexture(portrait)
    if f.CreateMaskTexture and p.AddMaskTexture then
      local m = f:CreateMaskTexture()
      m:SetAllPoints(p)
      m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      p:AddMaskTexture(m)
    end
    f.skinPortrait = p
  end
  return true
end

-- a window: background, the game's frame (a bronze line without it), a thin line in the
-- addon's colour under the top row (titleH below the content top; 0 = none).
-- opts.portrait = the logo in the round corner.
function Skin.Window(f, titleH, opts)
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetAllPoints()
  bg:SetColorTexture(Skin.BG[1], Skin.BG[2], Skin.BG[3], 0.98)
  f.skinBg = bg
  if not MetalNineSlice(f, opts and opts.portrait) then Skin.Edge(f, Skin.EDGE, 1, "ARTWORK") end
  if titleH and titleH > 0 then
    local line = f:CreateTexture(nil, "ARTWORK")
    local y = -titleH - Skin.Top(f)
    line:SetPoint("TOPLEFT", 12, y)
    line:SetPoint("TOPRIGHT", -12, y)
    line:SetHeight(1)
    local a = Skin.ACCENT
    line:SetColorTexture(a[1], a[2], a[3], 0.7)
    f.skinTitleLine = line
  end
  return f
end

-- how far the content moves down: the height of the title band inside the window
function Skin.Top(f) return f.skinTop or 0 end
-- where the content starts in a window whose title sits in the band: below the logo when
-- there is one (owner's test 11 Nov: a header was under the logo)
function Skin.ContentTop(f)
  if (f.skinTop or 0) > 0 then return f.skinPortrait and -56 or -(f.skinTop + 10) end
  return -44
end

-- the window title: centred in the title band, else at the top left
function Skin.PlaceTitle(fs, f, pad)
  fs:ClearAllPoints()
  local inside = f.skinTop or 0
  if inside > 0 then
    -- drawn above the metal, at the size of the game's own window titles
    if f.skinMetal and fs.SetParent then fs:SetParent(f.skinMetal) end
    if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", 7) end
    if fs.SetFontObject then fs:SetFontObject("GameFontNormal") end
    fs:SetPoint("CENTER", f, "TOP", 0, -inside / 2)
  else
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", pad or 16, -12)
  end
end

-- the close button of the game's windows (its own template, so it sits exactly where the
-- game puts it); a plain "X" from the caller without it
function Skin.Close(parent)
  for _, tpl in ipairs({ "UIPanelCloseButtonDefaultAnchors", "UIPanelCloseButton" }) do
    local ok, b = pcall(CreateFrame, "Button", nil, parent, tpl)
    if ok and b and (tpl ~= "UIPanelCloseButton" or b.GetNormalTexture and b:GetNormalTexture()) then
      if parent.skinMetal then b:SetFrameLevel((parent.skinMetal:GetFrameLevel() or 1) + 2) end
      if tpl ~= "UIPanelCloseButtonDefaultAnchors" then
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 1, 0)
      end
      b.skinTemplate = tpl
      return b
    end
  end
  return nil
end
-- where the close button goes: the game's place in its frame, else the top right inside
function Skin.PlaceClose(b, f)
  if b.skinTemplate == "UIPanelCloseButtonDefaultAnchors" then return end
  b:ClearAllPoints()
  if (f.skinTop or 0) > 0 then
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 0)
  else
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
  end
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
  t:SetHeight(1)
  if not Skin.Atlas(t, "Options_HorizontalDivider") then
    local e = Skin.EDGE
    t:SetColorTexture(e[1], e[2], e[3], 0.8)
  end
  return t
end
