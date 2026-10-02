-- Full Mana Forever
-- Shows a mana consumable only when it is off cooldown AND your mana deficit is at
-- least its maximum restore. Current mana is a secret value in Forever, so the addon
-- never reads it: a step curve is handed to UnitPowerPercent and the engine returns a
-- secret alpha that is applied straight to a frame. Nested frames multiply their alpha,
-- which gives "ready AND deficit big enough (AND enough HP for runes)".
-- Verified in the Forever beta: item cooldowns and max mana are readable in combat,
-- UnitPowerPercent works with a ColorCurve on a 0..1 scale.

local ADDON, ns = ...
local L = ns.L
ns.VERSION = "0.6.7"
local PREFIX = "|cff4fa3ffFMF|r: "
local MANA = 0 -- Enum.PowerType.Mana

local DEFAULTS = {
  point      = { "CENTER", "UIParent", "CENTER", 0, -120 }, -- turned into TOPLEFT on first load
  locked     = true,
  test       = false,
  debug      = false,
  scale100   = false,
  onlyCombat = false,
  showSolo   = true,    -- where to show: alone / in a party / in a raid (any combination)
  showParty  = true,
  showRaid   = true,
  language   = "auto",
  showAdvanced = false,
  pickMode   = "fit",   -- "fit": strongest item that does not overflow / "strongest": always the best
  thresholdMode = "max", -- "max": no waste / "avg": more drinks per fight
  showBar    = true,
  barPosition = "below", -- horizontal layout: "below" / "above" the icons
  vertical   = false,   -- icons in a column, mana bar standing next to them
  barSide    = "left",  -- vertical layout: bar "left" / "right" of the icons
  barThickness = 14,
  barLength  = 0,       -- 0 = as long as the icons (at least 3 icons)
  barColor   = "blue",
  iconGap    = 6,
  iconSize   = 44,
  runeMargin = 0.30, -- health% that must remain AFTER the rune hit
  enabled    = { potion = true, rune = true, gem = true, herb = true, gear = true },
  custom     = {},    -- { {id=, max=, group=}, ... } own items, highest priority in their group
  disabled   = {},    -- [itemID] = true: never suggest this item
}
ns.DEFAULTS = DEFAULTS

local db, anchor
local buttons = {}
local lists = {}
local warned = {}
ns.buttons = buttons

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
local function Print(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  print(PREFIX .. msg)
end
ns.Print = Print

local function Debug(key, msg)
  if db and db.debug and not warned["d:" .. key] then
    warned["d:" .. key] = true
    Print("|cffff9900debug|r " .. msg)
  end
end

local function WarnOnce(key, msg)
  if not warned[key] then
    warned[key] = true
    Print("|cffff4444" .. msg .. "|r")
  end
end

local function IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

local function CopyDefaults(src, dst)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then
        dst[k] = {}
        CopyDefaults(v, dst[k])
      elseif k ~= "custom" and k ~= "point" and k ~= "disabled" then
        CopyDefaults(v, dst[k])
      end
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local fullLists = {}

local playerClass
function ns.PlayerClass()
  if not playerClass then
    local ok, _, file = pcall(UnitClass, "player")
    if ok and file and not (issecretvalue and issecretvalue(file)) then playerClass = file end
  end
  return playerClass
end

-- group/item restricted to another class? (unknown class -> allow)
function ns.ForMyClass(x)
  if not x or not x.class then return true end
  local c = ns.PlayerClass()
  return not c or c == x.class
end

-- lists[i]: what the icons may use (enabled only); fullLists[i]: everything, for the item list window
function ns.RebuildLists()
  for i, group in ipairs(ns.GROUPS) do
    local full, active = {}, {}
    for _, c in ipairs(db.custom) do
      if (c.group or "potion") == group.key then
        c.custom = true
        full[#full + 1] = c
      end
    end
    for _, it in ipairs(group.items) do
      if ns.ForMyClass(it) then full[#full + 1] = it end
    end
    for _, it in ipairs(full) do
      if ns.IsItemEnabled(it) then active[#active + 1] = it end
    end
    fullLists[i], lists[i] = full, active
  end
end

function ns.FullList(i) return fullLists[i] or {} end

-- db.disabled[id]: true = off, false = on (overrides defaultOff), nil = item default
function ns.IsItemEnabled(it)
  local state = db.disabled[it.id]
  if state == nil then return not it.defaultOff end
  return not state
end

function ns.SetItemEnabled(id, on)
  db.disabled[id] = not on
  ns.RebuildLists()
end

-- solo / party / raid filter; unknown or unreadable group state -> show
local function GroupAllowed()
  local okR, raid = pcall(IsInRaid)
  local okG, group = pcall(IsInGroup)
  if not okR or not okG or IsSecret(raid) or IsSecret(group) then return true end
  if raid then return db.showRaid end
  if group then return db.showParty end
  return db.showSolo
end
ns.GroupAllowed = GroupAllowed

local function InBattleground()
  if not IsInInstance then return false end
  local _, kind = IsInInstance()
  return kind == "pvp"
end

------------------------------------------------------------------------
-- item state (readable in combat, verified in the beta)
------------------------------------------------------------------------
local CooldownState

local function IsEquipped(id)
  if C_Item.IsEquippedItem then return C_Item.IsEquippedItem(id) end
  return IsEquippedItem and IsEquippedItem(id)
end

local function OwnedItem(i)
  if ns.GROUPS[i].equipped then
    local fallback
    for _, it in ipairs(lists[i]) do
      if IsEquipped(it.id) then
        if CooldownState(it.id) then return it, 1 end
        fallback = fallback or it
      end
    end
    if fallback then return fallback, 1 end
    return nil
  end
  local bg = InBattleground()
  local preferReady, fallback, fallbackN = ns.GROUPS[i].preferReady
  for _, it in ipairs(lists[i]) do
    if it.pvp and not bg then
      -- battleground-only item: skip everywhere else
    else
    local n = C_Item.GetItemCount(it.id)
    if IsSecret(n) then
      Debug("countsecret", "item count is secret")
      return it, 1
    elseif n and n > 0 then
      if not preferReady or CooldownState(it.id) then return it, n end
      if not fallback then fallback, fallbackN = it, n end
    end
    end
  end
  return fallback, fallbackN
end

-- returns ready, secondsLeft
CooldownState = function(id)
  local s, d = C_Container.GetItemCooldown(id)
  if IsSecret(s) or IsSecret(d) then
    Debug("cdsecret", "item cooldown is secret - treating as ready")
    return true, 0
  end
  if not s or not d or d == 0 then return true, 0 end
  local left = s + d - GetTime()
  return left <= 0.05, math.max(left, 0)
end

-- restore used for thresholds: max ("no waste") or average ("max per fight")
local function Restore(it)
  if db.thresholdMode == "avg" and it.min then return (it.min + it.max) / 2 end
  return it.max
end
ns.Restore = function(it) return Restore(it) end

local function Threshold(item, maxMana)
  return 1 - Restore(item) / maxMana
end

-- groups whose items share one cooldown can stack several items in one slot ("bands")
local function CanBand(group)
  return not group.equipped and not group.preferReady
end

-- ready items of a shared-cooldown group, strongest first, one per distinct restore
local function BandCandidates(i)
  local out, seen, bg = {}, {}, InBattleground()
  for _, it in ipairs(lists[i]) do
    if not (it.pvp and not bg) then
      local n = C_Item.GetItemCount(it.id)
      if not IsSecret(n) and n and n > 0 and CooldownState(it.id) then
        out[#out + 1] = { it = it, n = n }
      end
    end
  end
  table.sort(out, function(a, b) return Restore(a.it) > Restore(b.it) end)
  local res = {}
  for _, c in ipairs(out) do
    local r = Restore(c.it)
    if not seen[r] and #res < 4 then seen[r] = true; res[#res + 1] = c end
  end
  return res
end

-- the mana% at which the group's first icon appears (for status + bar ticks)
local function FirstThreshold(i, maxMana)
  local group = ns.GROUPS[i]
  if db.pickMode == "fit" and CanBand(group) then
    local c = BandCandidates(i)
    if #c > 0 then return Threshold(c[#c].it, maxMana) end
    return nil
  end
  local item = OwnedItem(i)
  return item and Threshold(item, maxMana)
end

-- every mana% where the slot switches to another item (weakest first), for bar ticks
local function AllThresholds(i, maxMana)
  local group = ns.GROUPS[i]
  if db.pickMode == "fit" and CanBand(group) then
    local out, c = {}, BandCandidates(i)
    for k = #c, 1, -1 do out[#out + 1] = Threshold(c[k].it, maxMana) end
    return out
  end
  local t = FirstThreshold(i, maxMana)
  return t and { t } or {}
end

-- status for the options window
function ns.GetStatus(i)
  local item, n = OwnedItem(i)
  if not item then return nil end
  if db.pickMode == "fit" and CanBand(ns.GROUPS[i]) then
    local c = BandCandidates(i)
    if #c > 0 then item, n = c[#c].it, c[#c].n end
  end
  local ready, left = CooldownState(item.id)
  local maxMana = UnitPowerMax("player", MANA)
  local thr, hpThr
  if not IsSecret(maxMana) and maxMana and maxMana > 0 then
    thr = FirstThreshold(i, maxMana) or Threshold(item, maxMana)
  end
  local maxHP = UnitHealthMax("player")
  if item.hpCost and not IsSecret(maxHP) and maxHP and maxHP > 0 then
    hpThr = item.hpCost / maxHP + db.runeMargin
  end
  return item, n, ready, left, thr, hpThr
end

------------------------------------------------------------------------
-- curves (the engine compares, we never see the value)
------------------------------------------------------------------------
local function Scale() return db.scale100 and 100 or 1 end
local EPS = 0.0001

-- alpha 1 while lo < mana% <= hi (lo = nil: from 0), 0 elsewhere
local function BandCurve(lo, hi)
  local c = C_CurveUtil.CreateColorCurve()
  c:SetType(Enum.LuaCurveType.Step)
  if lo and lo >= 0 then
    c:AddPoint(0, CreateColor(1, 1, 1, 0))
    c:AddPoint((lo + EPS) * Scale(), CreateColor(1, 1, 1, 1))
  else
    c:AddPoint(0, CreateColor(1, 1, 1, 1))
  end
  if hi < 1 then
    c:AddPoint((math.max(hi, 0) + EPS) * Scale(), CreateColor(1, 1, 1, 0))
  end
  return c
end

local function ManaCurve(threshold) return BandCurve(nil, threshold) end

-- alpha 0 while health% < threshold, 1 at or above it
local function HealthCurve(threshold)
  local c = C_CurveUtil.CreateColorCurve()
  c:SetType(Enum.LuaCurveType.Step)
  c:AddPoint(0, CreateColor(1, 1, 1, 0))
  if threshold < 1 then
    c:AddPoint(math.max(threshold, 0) * Scale(), CreateColor(1, 1, 1, 1))
  end
  return c
end

local powerVariant, healthVariant

local function PowerColor(curve)
  local variants = {
    function() return UnitPowerPercent("player", MANA, false, curve) end,
    function() return UnitPowerPercent("player", MANA, curve) end,
  }
  for v, fn in ipairs(variants) do
    if powerVariant == nil or powerVariant == v then
      local ok, r = pcall(fn)
      if ok and type(r) == "table" then
        if powerVariant == nil then Debug("pv", "UnitPowerPercent variant " .. v) end
        powerVariant = v
        return r
      end
    end
  end
  WarnOnce("power", L.warnPower)
end

local function HealthColor(curve)
  local variants = {
    function() return UnitHealthPercent("player", false, curve) end,
    function() return UnitHealthPercent("player", curve) end,
  }
  for v, fn in ipairs(variants) do
    if healthVariant == nil or healthVariant == v then
      local ok, r = pcall(fn)
      if ok and type(r) == "table" then
        healthVariant = v
        return r
      end
    end
  end
  WarnOnce("health", L.warnHealth)
end

local function ApplyAlpha(frame, color)
  if not color then frame:SetAlpha(1) return end
  local ok = pcall(function() frame:SetAlpha(select(4, color:GetRGBA())) end)
  if not ok then
    WarnOnce("setalpha", L.warnAlpha)
    frame:SetAlpha(1)
  end
end

------------------------------------------------------------------------
-- frames
------------------------------------------------------------------------
local PLACEHOLDER = {
  potion = "Interface\\Icons\\INV_Potion_76",
  rune   = "Interface\\Icons\\INV_Misc_Rune_04",
  gem    = "Interface\\Icons\\INV_Misc_Gem_Ruby_01",
  herb   = "Interface\\Icons\\INV_Misc_QuestionMark",
  gear   = "Interface\\Icons\\INV_Jewelry_Talisman_07",
}
local TICK_COLOR = {
  potion = { 0.45, 0.75, 1 },
  rune   = { 0.75, 0.45, 1 },
  gem    = { 1, 0.35, 0.35 },
  herb   = { 0.4, 1, 0.5 },
  gear   = { 1, 0.8, 0.3 },
}
local MAX_LAYERS = 4

ns.BAR_COLORS = {
  { key = "blue",   top = { 0.30, 0.62, 1.00 }, bottom = { 0.06, 0.28, 0.78 } },
  { key = "light",  top = { 0.55, 0.85, 1.00 }, bottom = { 0.15, 0.50, 0.85 } },
  { key = "purple", top = { 0.72, 0.52, 1.00 }, bottom = { 0.38, 0.18, 0.78 } },
  { key = "teal",   top = { 0.35, 0.95, 0.85 }, bottom = { 0.05, 0.55, 0.55 } },
}

local function BarColor()
  for _, c in ipairs(ns.BAR_COLORS) do
    if c.key == db.barColor then return c end
  end
  return ns.BAR_COLORS[1]
end

-- 1 px frame around a region, drawn just outside it
local function Border(owner, region, layer, r, g, b, a, out)
  out = out or 1
  local t = {}
  local function edge(p1, p2, x1, y1, x2, y2, w, h)
    local e = owner:CreateTexture(nil, layer, nil, 7)
    e:SetColorTexture(r, g, b, a)
    e:SetPoint(p1, region, p1, x1, y1)
    e:SetPoint(p2, region, p2, x2, y2)
    if w then e:SetWidth(w) else e:SetHeight(h) end
    t[#t + 1] = e
  end
  edge("TOPLEFT", "TOPRIGHT", -out, out, out, out, nil, 1)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", -out, -out, out, -out, nil, 1)
  edge("TOPLEFT", "BOTTOMLEFT", -out, out, -out, -out, 1, nil)
  edge("TOPRIGHT", "BOTTOMRIGHT", out, out, out, -out, 1, nil)
  return t
end

local function OutlineFont(fs, size)
  pcall(function()
    local file, cur = fs:GetFont()
    if file then fs:SetFont(file, size or cur, "OUTLINE") end
  end)
end

-- one layer = one item icon inside a slot; its alpha is the item's mana band.
-- Everything that belongs to the icon (frame, shine, count) lives inside the layer,
-- so an icon that is "off" leaves nothing behind on the screen.
local function CreateLayer(parent)
  local l = CreateFrame("Frame", nil, parent)
  l:SetAllPoints()
  l.shadow = l:CreateTexture(nil, "BACKGROUND")
  l.shadow:SetPoint("TOPLEFT", -3, 3)
  l.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
  l.shadow:SetColorTexture(0, 0, 0, 0.45)
  l.icon = l:CreateTexture(nil, "ARTWORK")
  l.icon:SetAllPoints()
  l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- soft light from the top, dark edge at the bottom: a slightly "glassy" icon
  l.shine = l:CreateTexture(nil, "ARTWORK", nil, 2)
  l.shine:SetPoint("TOPLEFT")
  l.shine:SetPoint("TOPRIGHT")
  l.shine:SetColorTexture(1, 1, 1, 0.10)
  Border(l, l, "OVERLAY", 0, 0, 0, 1, 1)
  l.inner = Border(l, l, "OVERLAY", 1, 1, 1, 0.12, 0)
  l.count = l:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  l.count:SetPoint("BOTTOMRIGHT", -2, 2)
  OutlineFont(l.count)
  l.glow = l:CreateTexture(nil, "OVERLAY")
  l.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  l.glow:SetBlendMode("ADD")
  l.glow:SetVertexColor(0.3, 0.7, 1)
  l.glow:SetPoint("CENTER")
  local ag = l.glow:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(1)
  a:SetToAlpha(0.25)
  a:SetDuration(0.5)
  ag:Play()
  l:Hide()
  return l
end

local function CreateButton()
  local b = {}
  b.outer = CreateFrame("Frame", nil, anchor)   -- gate 1: ready (Show/Hide)
  b.hp = CreateFrame("Frame", nil, b.outer)      -- gate 2: enough HP (runes)
  b.hp:SetAllPoints()
  b.layers = {}
  for k = 1, MAX_LAYERS do b.layers[k] = CreateLayer(b.hp) end  -- gate 3: mana band per item
  b.outer:Hide()
  return b
end

-- mana bar next to the icons, drawn by the engine from the secret value, with ticks.
-- Vertical: the fill stands on the bottom, so spending mana lowers it from the top.
local bar
local function CreateBar()
  bar = CreateFrame("StatusBar", nil, anchor)
  bar:SetHeight(14)
  bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  -- the empty part is clearly lighter than the world behind it, so the end is always visible
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints()
  bar.bg:SetColorTexture(0.26, 0.28, 0.34, 0.92)
  bar.shadow = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
  bar.shadow:SetPoint("TOPLEFT", -3, 3)
  bar.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
  bar.shadow:SetColorTexture(0, 0, 0, 0.45)
  local top = CreateFrame("Frame", nil, bar)
  top:SetAllPoints()
  top:SetFrameLevel((bar:GetFrameLevel() or 1) + 3)
  bar.top = top
  -- glass highlight over half of the bar (top half, or left half when vertical)
  bar.gloss = top:CreateTexture(nil, "ARTWORK")
  bar.gloss:SetColorTexture(1, 1, 1, 0.10)
  Border(top, bar, "OVERLAY", 0, 0, 0, 1, 1)
  bar.ticks = {}
  for i = 1, #ns.GROUPS do
    bar.ticks[i] = {}
    for k = 1, MAX_LAYERS do
      local t = { back = top:CreateTexture(nil, "OVERLAY", nil, 1), front = top:CreateTexture(nil, "OVERLAY", nil, 2) }
      t.back:SetColorTexture(0, 0, 0, 0.85)
      t.back:SetPoint("TOPLEFT", t.front, "TOPLEFT", -1, 1)
      t.back:SetPoint("BOTTOMRIGHT", t.front, "BOTTOMRIGHT", 1, -1)
      t.back:Hide(); t.front:Hide()
      bar.ticks[i][k] = t
    end
  end
  bar.text = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  OutlineFont(bar.text)
  bar:Hide()
end

-- colors are re-applied on every layout change (option window, color pick)
local function PaintBar()
  local c = BarColor()
  local tex = bar:GetStatusBarTexture()
  local vertical = db.vertical
  local ok = tex and pcall(function()
    -- horizontal bar: light on top; vertical bar: light on the left
    if vertical then
      tex:SetGradient("HORIZONTAL", CreateColor(c.top[1], c.top[2], c.top[3], 1),
        CreateColor(c.bottom[1], c.bottom[2], c.bottom[3], 1))
    else
      tex:SetGradient("VERTICAL", CreateColor(c.bottom[1], c.bottom[2], c.bottom[3], 1),
        CreateColor(c.top[1], c.top[2], c.top[3], 1))
    end
  end)
  if not ok then bar:SetStatusBarColor(c.top[1], c.top[2], c.top[3]) end
end

-- "412 / 664" (vertical: two lines): the secret current value goes straight into the text
local textFails = 0
local function SetBarText(maxMana)
  if textFails > 20 then bar.text:SetText("") return end
  local fmt = "%d / %d"
  local ok = pcall(function()
    bar.text:SetText(string.format(fmt, UnitPower("player", MANA), maxMana))
  end)
  if not ok then
    textFails = textFails + 1
    bar.text:SetText("")
    Debug("bartext", "mana text could not be formatted")
  end
end

-- Buttons that are shown (item present and ready) are packed in a row (or a column),
-- so no empty gaps appear for groups you have nothing for. The mana check itself is
-- secret, so a ready item below its threshold still keeps its (invisible) slot.
local layoutKey
function ns.Layout(force)
  if not anchor then return end
  local size, gap, vertical = db.iconSize, db.iconGap or 6, db.vertical
  local key = ("%d|%d|%s|%s|%s|%d|%d|%s"):format(size, gap, tostring(vertical), db.barPosition,
    db.barSide, db.barThickness, db.barLength, db.barColor)
  for _, g in ipairs(ns.GROUPS) do key = key .. (db.enabled[g.key] and "e" or "d") end
  for _, b in ipairs(buttons) do key = key .. (b.outer:IsShown() and "1" or "0") end
  if key == layoutKey and not force then return end
  layoutKey = key
  local pos, count = 0, 0
  for _, b in ipairs(buttons) do
    b.outer:SetSize(size, size)
    for _, l in ipairs(b.layers) do
      l.glow:SetSize(size * 1.9, size * 1.9)
      l.shine:SetHeight(size * 0.45)
    end
    b.outer:ClearAllPoints()
    if vertical then
      b.outer:SetPoint("TOP", anchor, "TOP", 0, -pos)
    else
      b.outer:SetPoint("LEFT", anchor, "LEFT", pos, 0)
    end
    if b.outer:IsShown() then
      pos = pos + size + gap
      count = count + 1
    end
  end
  local span = math.max(pos - gap, size, count == 0 and size * 2 or 0)
  if vertical then anchor:SetSize(size, span) else anchor:SetSize(span, size) end
  if bar then
    -- auto length is fixed: room for every group this class can ever show (priest 4,
    -- mage 5). It does not follow lit icons or groups switched off in the options.
    local slots = 0
    for _, g in ipairs(ns.GROUPS) do
      if ns.ForMyClass(g) then slots = slots + 1 end
    end
    slots = math.max(slots, 3)
    local len = db.barLength and db.barLength > 0 and db.barLength or (size * slots + gap * (slots - 1))
    local thick = db.barThickness or 14
    if vertical then bar:SetSize(thick, len) else bar:SetSize(len, thick) end
    ns.PositionBar()
  end
end

-- bar under/over the icons, or left/right of the column; the label always sits on top
function ns.PositionBar()
  if not bar or not anchor then return end
  local vertical = db.vertical
  bar:ClearAllPoints()
  anchor.label:ClearAllPoints()
  bar.text:ClearAllPoints()
  bar.gloss:ClearAllPoints()
  bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
  if vertical then
    if db.barSide == "right" then
      bar:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    else
      bar:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
    end
    anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
    bar.text:SetPoint("TOP", bar, "BOTTOM", 0, -4)
    bar.gloss:SetPoint("TOPLEFT")
    bar.gloss:SetPoint("BOTTOMLEFT")
    bar.gloss:SetWidth(math.max(1, (db.barThickness or 14) * 0.45))
  else
    if db.barPosition == "above" then
      bar:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 6)
      anchor.label:SetPoint("BOTTOM", bar, "TOP", 0, 8)
    else
      bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
      anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
    end
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.gloss:SetPoint("TOPLEFT")
    bar.gloss:SetPoint("TOPRIGHT")
    bar.gloss:SetHeight(math.max(1, (db.barThickness or 14) * 0.45))
  end
  PaintBar()
end

function ns.ApplyLock()
  local unlocked = not db.locked
  anchor:EnableMouse(unlocked)
  anchor.bg:SetShown(unlocked)
  anchor.label:SetShown(unlocked)
end

function ns.OnLanguageChanged()
  if anchor then anchor.label:SetText(L.anchor) end
end

-- The frame changes size whenever icons appear or disappear (and when the frame is
-- unlocked every icon is shown). It is therefore always pinned by its TOPLEFT corner:
-- the first icon stays exactly where you dropped it, whatever the frame size.
local function PinTopLeft()
  local l, t = anchor:GetLeft(), anchor:GetTop()
  if not l or not t then return end
  anchor:ClearAllPoints()
  anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
  db.point = { "TOPLEFT", "UIParent", "BOTTOMLEFT", l, t }
end

local function IsPinned(p)
  return p and p[1] == "TOPLEFT" and p[3] == "BOTTOMLEFT"
end

function ns.ResetPosition()
  db.point = { unpack(DEFAULTS.point) }
  anchor:ClearAllPoints()
  anchor:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
  PinTopLeft()
end

local function CreateAnchor()
  anchor = CreateFrame("Frame", "FullManaForeverAnchor", UIParent)
  local p = db.point
  anchor:SetPoint(p[1], UIParent, p[3], p[4], p[5])
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetScript("OnDragStart", anchor.StartMoving)
  anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    PinTopLeft()
  end)
  anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
  anchor.bg:SetPoint("TOPLEFT", -4, 4)
  anchor.bg:SetPoint("BOTTOMRIGHT", 4, -4)
  anchor.bg:SetColorTexture(0, 0.4, 1, 0.35)
  anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
  anchor.label:SetText(L.anchor)

  for i = 1, #ns.GROUPS do buttons[i] = CreateButton() end
  CreateBar()
  ns.PositionBar()
  ns.Layout(true)
  ns.ApplyLock()
  -- positions saved before 0.6.7 were CENTER-based: convert once, keeping the spot
  if not IsPinned(db.point) then PinTopLeft() end
end

------------------------------------------------------------------------
-- update loop
------------------------------------------------------------------------
local function SetLayer(l, id, n, texture)
  if l.itemID ~= id or not id then
    l.icon:SetTexture(texture or C_Item.GetItemIconByID(id))
    l.itemID = id
  end
  l.icon:SetDesaturated(id == nil)
  l.count:SetText(n and n > 1 and n or "")
end

local function HideLayers(b, from)
  for k = from, MAX_LAYERS do
    local l = b.layers[k]
    l:Hide()
    l.curveKey = nil
  end
end

local function ShowPreview(i, b, item, n)
  local l = b.layers[1]
  local ph
  if not item then
    local first
    for _, it in ipairs(ns.GROUPS[i].items) do
      if not first and ns.ForMyClass(it) then first = it end
    end
    ph = first and C_Item.GetItemIconByID(first.id) or PLACEHOLDER[ns.GROUPS[i].key]
  end
  SetLayer(l, item and item.id, n, ph)
  l:SetAlpha(1)
  l.curveKey = nil
  l:Show()
  HideLayers(b, 2)
  b.hp:SetAlpha(1)
  b.outer:Show()
end

local function ApplyHpGate(b, hpCost, maxHP)
  if hpCost and not db.test and not IsSecret(maxHP) and maxHP and maxHP > 0 then
    local t = hpCost / maxHP + db.runeMargin
    local hkey = ("%.4f"):format(t)
    if b.hpKey ~= hkey then b.hpCurve, b.hpKey = HealthCurve(t), hkey end
    local hc = HealthColor(b.hpCurve)
    if hc then ApplyAlpha(b.hp, hc) else b.hp:SetAlpha(0) end -- no HP check -> never risk it
  else
    b.hp:SetAlpha(1)
  end
end

local function ApplyBand(l, lo, hi)
  local key = ("%s|%.4f"):format(lo and ("%.4f"):format(lo) or "-", hi)
  if l.curveKey ~= key then l.curve, l.curveKey = BandCurve(lo, hi), key end
  ApplyAlpha(l, PowerColor(l.curve))
end

local function UpdateButton(i, b, maxMana, maxHP)
  local group = ns.GROUPS[i]
  if not db.enabled[group.key] or not ns.ForMyClass(group) then b.outer:Hide() return end

  local item, n = OwnedItem(i)
  if not db.locked then ShowPreview(i, b, item, n) return end  -- positioning preview

  if db.onlyCombat and not db.test and not InCombatLockdown() then b.outer:Hide() return end
  if not db.test and not GroupAllowed() then b.outer:Hide() return end
  if not item and db.test then ShowPreview(i, b, nil, nil) return end  -- test: grey placeholder

  -- which items go into the slot, and their mana bands
  local cands
  if db.pickMode == "fit" and CanBand(group) and not db.test then
    cands = BandCandidates(i)
  elseif item and CooldownState(item.id) then
    cands = { { it = item, n = n } }
  else
    cands = {}
  end
  if #cands == 0 then b.outer:Hide() return end

  local hpCost
  for k, c in ipairs(cands) do
    local l = b.layers[k]
    SetLayer(l, c.it.id, c.n)
    if db.test then
      l:SetAlpha(1)
      l.curveKey = nil
    else
      -- strongest first: band (threshold of the stronger item, own threshold]
      local lo = k > 1 and Threshold(cands[k - 1].it, maxMana) or nil
      ApplyBand(l, lo, Threshold(c.it, maxMana))
    end
    l:Show()
    if c.it.hpCost then hpCost = math.max(hpCost or 0, c.it.hpCost) end
  end
  HideLayers(b, #cands + 1)
  ApplyHpGate(b, hpCost, maxHP)
  b.outer:Show()
end

local function BarVisible()
  if not db.showBar then return false end
  if not db.locked or db.test then return true end
  if not GroupAllowed() then return false end
  return not db.onlyCombat or InCombatLockdown()
end

local function UpdateBar(maxMana)
  if not bar then return end
  if not BarVisible() then bar:Hide() return end
  bar:SetMinMaxValues(0, maxMana)
  local ok = pcall(bar.SetValue, bar, UnitPower("player", MANA))
  if not ok then bar:SetValue(maxMana) end
  SetBarText(maxMana)
  local vertical = db.vertical
  local len = (vertical and bar:GetHeight() or bar:GetWidth()) or 0
  local thick = db.barThickness or 14
  for i, group in ipairs(ns.GROUPS) do
    local list = (db.enabled[group.key] and ns.ForMyClass(group)) and AllThresholds(i, maxMana) or {}
    local c = TICK_COLOR[group.key] or { 1, 1, 1 }
    for k, t in ipairs(bar.ticks[i]) do
      local thr = list[k]
      if thr and thr > 0 and thr < 1 then
        -- first tick (the icon lights up) is long, the switches to stronger items are short
        local long = k == 1 and thick + 6 or thick
        t.front:SetColorTexture(c[1], c[2], c[3], 1)
        t.front:ClearAllPoints()
        if vertical then
          t.front:SetSize(long, 2)
          t.front:SetPoint("CENTER", bar, "BOTTOM", 0, len * thr)
        else
          t.front:SetSize(2, long)
          t.front:SetPoint("CENTER", bar, "LEFT", len * thr, 0)
        end
        t.front:Show(); t.back:Show()
      else
        t.front:Hide(); t.back:Hide()
      end
    end
  end
  bar:Show()
end

local function Update()
  -- the frame rect may not be known yet at login: convert old positions on the first tick
  if anchor and not IsPinned(db.point) then PinTopLeft() end
  local maxMana = UnitPowerMax("player", MANA)
  if IsSecret(maxMana) or not maxMana or maxMana <= 0 then
    Debug("maxmana", "max mana unavailable or secret")
    for _, b in ipairs(buttons) do b.outer:Hide() end
    if bar then bar:Hide() end
    return
  end
  local maxHP = UnitHealthMax("player")
  for i, b in ipairs(buttons) do
    UpdateButton(i, b, maxMana, maxHP)
  end
  ns.Layout()
  UpdateBar(maxMana)
end

local function SafeUpdate()
  local ok, err = pcall(Update)
  if not ok then WarnOnce("update", L.warnUpdate:format(tostring(err))) end
end

function ns.InvalidateCurves()
  for _, b in ipairs(buttons) do
    b.hpKey = nil
    for _, l in ipairs(b.layers) do l.curveKey = nil end
  end
end

------------------------------------------------------------------------
-- macros were removed in 0.6.7 (a macro cannot see mana, so it never matched the icon).
-- Users who had them switched on get their FMF_* macros deleted once, out of combat.
------------------------------------------------------------------------
local OLD_MACROS = { "FMF_Potion", "FMF_Rune", "FMF_Gem", "FMF_Other" }

local function DeleteOldMacros()
  if not db.cleanMacros then return end
  if InCombatLockdown() or not (GetMacroIndexByName and DeleteMacro) then return end
  for _, name in ipairs(OLD_MACROS) do
    local idx = GetMacroIndexByName(name)
    if idx and idx > 0 then pcall(DeleteMacro, idx) end
  end
  db.cleanMacros = nil
end

------------------------------------------------------------------------
-- probe
------------------------------------------------------------------------
local function Probe()
  local function yn(v) return v and "yes" or "no" end
  Print("v%s combat=%s  secretMana=%s  secretMax=%s", ns.VERSION, tostring(InCombatLockdown()),
    tostring(IsSecret(UnitPower("player", MANA))), tostring(IsSecret(UnitPowerMax("player", MANA))))
  Print("API: UnitPowerPercent=%s UnitHealthPercent=%s C_CurveUtil=%s LuaCurveType=%s",
    yn(UnitPowerPercent), yn(UnitHealthPercent), yn(C_CurveUtil and C_CurveUtil.CreateColorCurve),
    yn(Enum and Enum.LuaCurveType))
  local ok, err = pcall(function()
    local c = ManaCurve(0.5)
    local lo, hi = c:Evaluate(0.2 * Scale()), c:Evaluate(0.8 * Scale())
    Print("curve test (expect 1 / 0): %s / %s", tostring(select(4, lo:GetRGBA())), tostring(select(4, hi:GetRGBA())))
    local r = PowerColor(c)
    Print("UnitPowerPercent+curve: %s (variant %s)", r and "ok" or "FAILED", tostring(powerVariant))
  end)
  if not ok then Print("curve probe error: %s", tostring(err)) end
  Print("scale100=%s test=%s onlyCombat=%s custom=%d", tostring(db.scale100), tostring(db.test),
    tostring(db.onlyCombat), #db.custom)
end

------------------------------------------------------------------------
-- slash commands
------------------------------------------------------------------------
SLASH_FULLMANAFOREVER1 = "/fmf"
SlashCmdList.FULLMANAFOREVER = function(msg)
  local args = {}
  for w in (msg or ""):gmatch("%S+") do args[#args + 1] = w:lower() end
  local cmd = args[1]

  if not cmd or cmd == "config" or cmd == "options" then
    if ns.ToggleOptions then ns.ToggleOptions() else Print(L.help) end
  elseif cmd == "items" or cmd == "list" then
    if ns.ToggleLibrary then ns.ToggleLibrary() end
  elseif cmd == "hold" then
    db.enabled.potion = not db.enabled.potion
    Print(db.enabled.potion and L.holdOff or L.holdOn)
  elseif cmd == "unlock" then
    db.locked = false; ns.ApplyLock(); Print(L.unlocked)
  elseif cmd == "lock" then
    db.locked = true; ns.ApplyLock(); Print(L.locked)
  elseif cmd == "test" then
    db.test = not db.test; Print(db.test and L.testOn or L.testOff)
  elseif cmd == "item" and args[2] == "clear" then
    wipe(db.custom); ns.RebuildLists(); Print(L.itemClear)
  elseif cmd == "item" then
    local id, amount = tonumber(args[2]), tonumber(args[3])
    if not id or not amount then Print(L.itemUsage) return end
    ns.AddCustom(id, amount, args[4])
  elseif cmd == "probe" then
    Probe()
  elseif cmd == "debug" then
    db.debug = not db.debug; wipe(warned); Print(db.debug and L.debugOn or L.debugOff)
  elseif cmd == "scale" then
    db.scale100 = not db.scale100
    ns.InvalidateCurves()
    Print("scale100 = %s", tostring(db.scale100))
  elseif cmd == "reset" then
    ns.ResetPosition(); Print(L.reset)
  else
    Print(L.help)
  end
  if ns.RefreshOptions then ns.RefreshOptions() end
end

-- only items with a Use effect can restore mana
local function ValidateItem(id)
  local itemID = C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(id)
  if not itemID then return false, L.errUnknown:format(id) end
  local spell = C_Item.GetItemSpell and C_Item.GetItemSpell(id)
  if spell then return true end
  if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(id) then
    if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return false, L.errLoading:format(id)
  end
  return false, L.errNoUse:format(id)
end

function ns.AddCustom(id, amount, group)
  local ok, err = ValidateItem(id)
  if not ok then Print("|cffff4444" .. err .. "|r") return false end
  local valid = false
  for _, g in ipairs(ns.GROUPS) do if g.key == group then valid = true end end
  if not valid then group = "potion" end
  for i = #db.custom, 1, -1 do
    if db.custom[i].id == id then table.remove(db.custom, i) end
  end
  table.insert(db.custom, 1, { id = id, max = amount, group = group })
  ns.RebuildLists()
  Print(L.itemAdded, id, amount)
  return true
end

function ns.RemoveCustom(id)
  for i = #db.custom, 1, -1 do
    if db.custom[i].id == id then table.remove(db.custom, i) end
  end
  ns.RebuildLists()
end

-- addon compartment (minimap addon menu) entry
function FullManaForever_OnCompartmentClick()
  if ns.ToggleOptions then ns.ToggleOptions() end
end

------------------------------------------------------------------------
-- boot
------------------------------------------------------------------------
local function InitDB()
  FullManaForeverDB = FullManaForeverDB or {}
  db = FullManaForeverDB
  CopyDefaults(DEFAULTS, db)
  if (db.dbVersion or 0) < 2 then
    if db.runeMargin and db.runeMargin < 0.30 then db.runeMargin = 0.30 end
    db.dbVersion = 2
  end
  if db.dbVersion < 3 then
    for _, c in ipairs(db.custom) do c.group = c.group or "potion" end
    db.dbVersion = 3
  end
  if db.dbVersion < 4 then
    if db.macros then db.cleanMacros = true end -- only users who had them on
    db.macros = nil
    db.dbVersion = 4
  end
  ns.SetLanguage(db.language)
  ns.db = db
  ns.RebuildLists()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    InitDB()
  elseif event == "PLAYER_REGEN_ENABLED" then
    DeleteOldMacros()
  elseif event == "PLAYER_LOGIN" then
    if not db then InitDB() end -- saved variables not delivered (old beta builds)
    ns.RebuildLists() -- player class is known now
    CreateAnchor()
    if ns.InitOptions then
      local ok, err = pcall(ns.InitOptions)
      if not ok then Print(L.warnOptions, tostring(err)) end
    end
    C_Timer.NewTicker(0.1, SafeUpdate)
    pcall(self.RegisterEvent, self, "PLAYER_REGEN_ENABLED")
    DeleteOldMacros()
    Print(L.loaded, ns.VERSION)
  end
end)
