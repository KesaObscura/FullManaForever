-- Full Mana Forever
-- Shows a mana consumable only when it is off cooldown AND your mana deficit is at
-- least what it restores (maximum by default, average in "More per fight"). Current mana is a secret value in Forever, so the addon
-- never reads it: a step curve is handed to UnitPowerPercent and the engine returns a
-- secret alpha that is applied straight to a frame. Nested frames multiply their alpha,
-- which gives "ready AND deficit big enough (AND enough HP for runes)".
-- Verified in the Forever beta: item cooldowns and max mana are readable in combat,
-- UnitPowerPercent works with a ColorCurve on a 0..1 scale.

local ADDON, ns = ...
local L = ns.L
ns.VERSION = "0.8.3"
local PREFIX = "|cff4fa3ffFMF|r: "
local MANA = 0 -- Enum.PowerType.Mana
local MAX_LAYERS = 4 -- items stacked in one slot (one per distinct restore value)
local MAX_RESTORE = 99999 -- sanity limit for own items

local DEFAULTS = {
  point      = { "CENTER", "UIParent", "CENTER", 0, -120 }, -- turned into TOPLEFT on first load
  locked     = true,
  debug      = false,
  scale100   = false,
  onlyCombat = false,
  showSolo   = true,    -- where to show: alone / in a party / in a raid (any combination)
  showParty  = true,
  showRaid   = true,
  language   = "auto",
  pickMode   = "fit",   -- "fit": strongest item that does not overflow / "strongest": always the best
  thresholdMode = "max", -- "max": no waste / "avg": more drinks per fight
  showBar    = true,
  fsr        = true,    -- five-second rule countdown on the mana bar
  regenText  = true,    -- current mana regen next to the mana bar (also without the bar)
  textFree   = false,   -- mana numbers, rule seconds and regen can be dragged (frame unlocked)
  textPoints = {},      -- [mana|fsr|regen] = { x, y }: dragged text centers, UIParent units
  manaTextOn = true,    -- mana numbers at the bar (also without the bar)
  manaText   = "number", -- how: "number" / "percent" / "both"
  manaScale  = 1,       -- text size of the mana numbers
  fsrScale   = 1,       -- text size of the rule's seconds (1 = 100 %)
  regenScale = 1,       -- text size of the regen number
  barPosition = "below", -- horizontal layout: "below" / "above" the icons
  vertical   = false,   -- icons in a column, mana bar standing next to them
  barSide    = "left",  -- vertical layout: bar "left" / "right" of the icons
  barThickness = 14,
  barLength  = 0,       -- 0 = auto: room for every group switched on (at least 3)
  barColor   = "blue",
  iconGap    = 6,
  iconSize   = 44,
  runeMargin = 0.30, -- health% that must remain AFTER the rune hit (also Life Tap)
  spellThreshold = 0.50, -- own mana spells (Evocation, Innervate, ...) light up at or below this mana%
  enabled    = { potion = true, rune = true, gem = true, herb = true, gear = true, spell = true },
  custom     = {},    -- { {id=, max=, group=}, ... } own items, highest priority in their group
  disabled   = {},    -- [itemID] = true: never suggest this item
}

local db, anchor
local buttons = {}
local lists = {}
local warned = {}

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
local candStamp = {} -- per group: tick in which BandCandidates was computed

-- flags of a known item that an own entry for the same id keeps (warnings, safety)
local INHERIT = { "sleep", "pvp", "class", "hpCost" }

function ns.RebuildLists()
  local own, known = {}, {} -- own: [group key][id] = true
  for _, g in ipairs(ns.GROUPS) do
    own[g.key] = {}
    for _, it in ipairs(g.items) do known[it.id] = it end
  end
  for _, c in ipairs(db.custom) do
    local mine = own[c.group or "potion"]
    if mine then mine[c.id] = true end
    local base = known[c.id]
    if base then
      for _, k in ipairs(INHERIT) do c[k] = base[k] end
    end
  end
  for i, group in ipairs(ns.GROUPS) do
    local full, active = {}, {}
    for _, c in ipairs(db.custom) do
      if (c.group or "potion") == group.key then
        c.custom = true
        full[#full + 1] = c
      end
    end
    -- an own entry for a known item replaces it in the same group (no double row/layer)
    for _, it in ipairs(group.items) do
      if ns.ForMyClass(it) and not own[group.key][it.id] then full[#full + 1] = it end
    end
    for _, it in ipairs(full) do
      if ns.IsItemEnabled(it) then active[#active + 1] = it end
    end
    fullLists[i], lists[i] = full, active
  end
  wipe(candStamp)
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

local function InBattleground()
  if not IsInInstance then return false end
  local _, kind = IsInInstance()
  return kind == "pvp"
end

------------------------------------------------------------------------
-- level requirement: an item you cannot use yet is never suggested.
-- The required level comes from the game's item data (the "Requires Level" line);
-- while the game has not loaded an item yet, it is not hidden.
------------------------------------------------------------------------
local reqLevel, reqAsked = {}, {} -- [itemID] = required level (0 = none) / load requested
local playerLevel                 -- read once per tick; nil = unknown -> no level filter

function ns.RequiredLevel(id)
  local v = reqLevel[id]
  if v ~= nil then return v end
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not info then reqLevel[id] = 0 return 0 end
  local ok, name, _, _, _, minLevel = pcall(info, id)
  if ok and name and type(minLevel) == "number" and not IsSecret(minLevel) then
    reqLevel[id] = minLevel
    return minLevel
  end
  if not reqAsked[id] and C_Item and C_Item.RequestLoadItemDataByID then
    reqAsked[id] = true
    pcall(C_Item.RequestLoadItemDataByID, id)
  end
end

local function ReadPlayerLevel()
  local ok, lvl = pcall(UnitLevel, "player")
  if ok and type(lvl) == "number" and not IsSecret(lvl) and lvl > 0 then return lvl end
end

-- the level this item still needs, or nil when you can use it (or nothing is known)
function ns.LevelTooLow(it)
  local lvl = playerLevel or ReadPlayerLevel()
  if not lvl then return nil end
  local need = ns.RequiredLevel(it.id)
  if need and need > lvl then return need end
end

-- skipped everywhere: battleground-only items outside battlegrounds, items above your level
local function Usable(it, bg)
  return (bg or not it.pvp) and not ns.LevelTooLow(it)
end

------------------------------------------------------------------------
-- item state (readable in combat, verified in the beta)
------------------------------------------------------------------------
local CooldownState

local function IsEquipped(id)
  if C_Item.IsEquippedItem then return C_Item.IsEquippedItem(id) end
  return IsEquippedItem and IsEquippedItem(id)
end
ns.IsEquipped = IsEquipped

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
    if Usable(it, bg) then
      local n = C_Item.GetItemCount(it.id)
      if IsSecret(n) then
        -- never seen in Forever; assume the item is there rather than hide the group
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
-- seconds; anything this short is the cooldown a wand shot puts on every item (and spell), not
-- the item's own (mana items have minutes). Bows and melee swings put none (owner, 0.8.1);
-- 5 s leaves room for slow wands.
local SHORT_CD = 5
local longUntil = {} -- [item] = GetTime() when its own (long) cooldown ends
-- the last short cooldown seen on any item: the game puts it on spells too, where it cannot be
-- read in combat, so the spell icon borrows it for its sweep
local lockStart, lockDur
CooldownState = function(id)
  local s, d, enable = C_Container.GetItemCooldown(id)
  if IsSecret(s) or IsSecret(d) or IsSecret(enable) then
    Debug("cdsecret", "item cooldown is secret - treating as ready")
    return true, 0
  end
  if s and d and d > 0 and d <= SHORT_CD and s + d > GetTime() then lockStart, lockDur = s, d end
  if s and d and d > SHORT_CD then longUntil[id] = s + d end
  -- the game may report a wand shot's short cooldown while the item's own still runs
  local own = longUntil[id]
  if own and d and d <= SHORT_CD then
    local left = own - GetTime()
    if left > 0.05 then return false, left end
    longUntil[id] = nil
  end
  -- a few seconds: a wand shot, not the item's own cooldown; counting it hid every potion
  -- while wanding (the icon shows the short wait as a sweep instead, see ApplySweep)
  if d and d > 0 and d <= SHORT_CD then return true, 0 end
  -- enable 0: the cooldown waits for something (e.g. the end of combat) before it runs
  if enable == 0 or enable == false then return false, (d and d > 0) and d or 0 end
  if not s or not d or d == 0 then return true, 0 end
  local left = s + d - GetTime()
  return left <= 0.05, math.max(left, 0)
end
ns.CooldownState = function(id) return CooldownState(id) end

-- start, duration of a short item cooldown (wand shot) that is still running, else nil
local function ShortCooldown(id)
  local s, d = C_Container.GetItemCooldown(id)
  if IsSecret(s) or IsSecret(d) or not s or not d or d <= 0 or d > SHORT_CD then return nil end
  if s + d <= GetTime() then return nil end
  return s, d
end

-- restore used for thresholds: max ("No waste") or average ("More per fight")
local function Restore(it)
  if db.thresholdMode == "avg" and it.min then return (it.min + it.max) / 2 end
  return it.max
end

-- mana% (0..1) at or below which the whole item fits into the missing mana
local function Threshold(item, maxMana)
  local t = 1 - Restore(item) / maxMana
  if t < 0 then return 0 end
  if t > 1 then return 1 end
  return t
end

-- groups whose items share one cooldown can stack several items in one slot ("bands")
local function CanBand(group)
  return not group.equipped and not group.preferReady and not group.spells
end

-- strongest first; equal restore: never the sleep potion, then list order (own items first)
local function ByRestore(a, b)
  if a.r ~= b.r then return a.r > b.r end
  if (a.it.sleep and true) ~= (b.it.sleep and true) then return not a.it.sleep end
  return a.idx < b.idx
end

-- ready items of a shared-cooldown group, strongest first, one per distinct restore.
-- Called several times per tick (icons, bar, options), so the result is computed once
-- per tick and all tables are reused: nothing is allocated in steady state.
local candTick = 0
local candRes, candAll, candPool, seen = {}, {}, {}, {}

local function BandCandidates(i)
  local res = candRes[i]
  if res and candStamp[i] == candTick then return res end
  res = res or {}
  candRes[i] = res
  local all = candAll[i] or {}
  candAll[i] = all
  local pool = candPool[i] or {}
  candPool[i] = pool
  wipe(res); wipe(all); wipe(seen)
  local bg = InBattleground()
  for idx, it in ipairs(lists[i]) do
    if Usable(it, bg) then
      local n = C_Item.GetItemCount(it.id)
      if not IsSecret(n) and n and n > 0 and CooldownState(it.id) then
        local e = pool[#all + 1] or {}
        pool[#all + 1] = e
        e.it, e.n, e.r, e.idx = it, n, Restore(it), idx
        all[#all + 1] = e
      end
    end
  end
  table.sort(all, ByRestore)
  for _, c in ipairs(all) do
    if not seen[c.r] and #res < MAX_LAYERS then seen[c.r] = true; res[#res + 1] = c end
  end
  candStamp[i] = candTick
  return res
end

-- the mana% at which the group's first icon appears (for status + bar ticks)
local function FirstThreshold(i, maxMana)
  local group = ns.GROUPS[i]
  if group.spells then
    -- the spell the icon would show (Life Tap has its own threshold), else the first known
    local sp = ns.Spells.Candidate() or ns.Spells.FirstKnown()
    return sp and ns.Spells.Threshold(sp, maxMana)
  end
  if db.pickMode == "fit" and CanBand(group) then
    local c = BandCandidates(i)
    if #c > 0 then return Threshold(c[#c].it, maxMana) end
    return nil
  end
  local item = OwnedItem(i)
  return item and Threshold(item, maxMana)
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
    thr = Threshold(item, maxMana)
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

-- two argument orders were seen during the beta; the working one is remembered and
-- probed again whenever it stops working (e.g. after a client patch)
local function TryPower(v, curve)
  if v == 1 then return pcall(UnitPowerPercent, "player", MANA, false, curve) end
  return pcall(UnitPowerPercent, "player", MANA, curve)
end

local function TryHealth(v, curve)
  if v == 1 then return pcall(UnitHealthPercent, "player", false, curve) end
  return pcall(UnitHealthPercent, "player", curve)
end

local function EngineColor(try, variant, curve)
  if variant then
    local ok, r = try(variant, curve)
    if ok and type(r) == "table" then return r, variant end
  end
  for v = 1, 2 do
    if v ~= variant then
      local ok, r = try(v, curve)
      if ok and type(r) == "table" then return r, v end
    end
  end
end

local function PowerColor(curve)
  local r, v = EngineColor(TryPower, powerVariant, curve)
  if r then
    if v ~= powerVariant then Debug("pv" .. v, "UnitPowerPercent variant " .. v) end
    powerVariant = v
    return r
  end
  powerVariant = nil
  WarnOnce("power", L.warnPower)
end

local function HealthColor(curve)
  local r, v = EngineColor(TryHealth, healthVariant, curve)
  if r then healthVariant = v return r end
  healthVariant = nil
  WarnOnce("health", L.warnHealth)
end

-- applies the engine's (secret) alpha; without a usable answer the frame gets failAlpha.
-- Mana and HP gates fail closed (0): a hidden icon costs nothing, a wrong one wastes a potion.
local function ApplyAlpha(frame, color, failAlpha)
  if color then
    local ok, _, _, _, a = pcall(color.GetRGBA, color)
    if ok and pcall(frame.SetAlpha, frame, a) then return end
    WarnOnce("setalpha", L.warnAlpha)
  end
  frame:SetAlpha(failAlpha)
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
  spell  = { 0.3, 1, 1 },
}
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

-- outlined text. The game's own "...Outline" font objects keep the whole font family
-- (Latin, Cyrillic, Korean, Chinese). Setting a font file by hand keeps only that one file:
-- fine for digits, but letters of other alphabets turn into boxes, so text with letters
-- (lettersToo) is never switched to a single file.
local function OutlineFont(fs, template, lettersToo)
  local obj = template and _G[template .. "Outline"]
  if obj then fs:SetFontObject(obj) return end
  if lettersToo then return end
  pcall(function()
    local file, cur = fs:GetFont()
    if file then fs:SetFont(file, cur, "OUTLINE") end
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
  -- the game blocks items for a moment after each wand shot: the icon stays (the potion
  -- fits, stop shooting and drink) and a sweep shows the wait, like on the action bar
  local okCd, sweep = pcall(CreateFrame, "Cooldown", nil, l, "CooldownFrameTemplate")
  if okCd and sweep then
    sweep:SetAllPoints(l.icon)
    if sweep.SetHideCountdownNumbers then sweep:SetHideCountdownNumbers(true) end
    if sweep.SetDrawEdge then sweep:SetDrawEdge(false) end
    if sweep.SetDrawBling then sweep:SetDrawBling(false) end -- no flash after every shot
    l.sweep = sweep
  end
  -- "/fmf hold": the word on a held potion. Inside the layer, so the mana band hides it
  -- together with the icon; its own frame, so the sweep cannot cover it
  local holdTop = CreateFrame("Frame", nil, l)
  holdTop:SetAllPoints()
  holdTop:SetFrameLevel((l:GetFrameLevel() or 1) + 3)
  l.holdText = holdTop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  OutlineFont(l.holdText, "GameFontNormal", true)
  l.holdText:SetPoint("CENTER")
  l.holdText:Hide()
  -- soft light from the top that fades out downwards: a slightly "glassy" icon. A flat
  -- strip left a hard line in the middle that looked like a half-full icon
  l.shine = l:CreateTexture(nil, "ARTWORK", nil, 2)
  l.shine:SetPoint("TOPLEFT")
  l.shine:SetPoint("TOPRIGHT")
  l.shine:SetColorTexture(1, 1, 1, 1)
  if not pcall(l.shine.SetGradient, l.shine, "VERTICAL", CreateColor(1, 1, 1, 0),
      CreateColor(1, 1, 1, 0.14)) then
    l.shine:Hide() -- no hard line without a gradient
  end
  Border(l, l, "OVERLAY", 0, 0, 0, 1, 1)
  l.inner = Border(l, l, "OVERLAY", 1, 1, 1, 0.12, 0)
  l.count = l:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  l.count:SetPoint("BOTTOMRIGHT", -2, 2)
  OutlineFont(l.count, "NumberFontNormal")
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

-- "/fmf hold": mana potions are not suggested until the end of the next fight (a fight that
-- is already running counts). Not saved: a reload ends it too. The "Mana potions" switch
-- is left alone.
local held, heldFightSeen = false, false
function ns.IsHeld() return held end
function ns.SetHold(on)
  held = on and true or false
  heldFightSeen = held and InCombatLockdown() and true or false
end
local holdFrame = CreateFrame("Frame")
holdFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
holdFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
holdFrame:SetScript("OnEvent", function(_, event)
  if not held then return end
  if event == "PLAYER_REGEN_DISABLED" then
    heldFightSeen = true
  elseif heldFightSeen then
    ns.SetHold(false)
    Print(L.holdOff)
    if ns.RefreshOptions then ns.RefreshOptions() end
  end
end)

-- mana bar next to the icons, drawn by the engine from the secret value, with ticks.
-- Vertical: the fill stands on the bottom, so spending mana lowers it from the top.
local bar
-- a frame for one text around the bar; dragged centers are saved in screen (UIParent) units,
-- because the frame's own units change with the text size
local TEXT_KEYS = { mana = "manaBox", fsr = "fsrBox", regen = "regenBox" }
local function TextScale(key)
  if key == "fsr" then return db.fsrScale or 1 end
  if key == "regen" then return db.regenScale or 1 end
  return db.manaScale or 1
end

local function CreateTextBox(key, width)
  local box = CreateFrame("Frame", nil, UIParent)
  box:SetSize(width, 16)
  box:SetMovable(true)
  box:SetClampedToScreen(true)
  box:RegisterForDrag("LeftButton")
  box:SetScript("OnDragStart", box.StartMoving)
  box:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    local scale = self:GetScale() or 1
    if x and y then db.textPoints[key] = { x * scale, y * scale } end
    ns.PositionBar()
  end)
  box.bg = box:CreateTexture(nil, "BACKGROUND")
  box.bg:SetAllPoints()
  box.bg:SetColorTexture(0, 0.4, 1, 0.35)
  box.bg:Hide()
  box:Hide()
  return box
end

local function TextFree(key) return db.textFree and db.textPoints[key] ~= nil end

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
    local c = TICK_COLOR[ns.GROUPS[i].key] or { 1, 1, 1 }
    for k = 1, MAX_LAYERS do
      local t = { back = top:CreateTexture(nil, "OVERLAY", nil, 1), front = top:CreateTexture(nil, "OVERLAY", nil, 2) }
      t.front:SetColorTexture(c[1], c[2], c[3], 1)
      t.back:SetColorTexture(0, 0, 0, 0.85)
      t.back:SetPoint("TOPLEFT", t.front, "TOPLEFT", -1, 1)
      t.back:SetPoint("BOTTOMRIGHT", t.front, "BOTTOMRIGHT", 1, -1)
      t.back:Hide(); t.front:Hide()
      bar.ticks[i][k] = t
    end
  end
  -- five-second rule: a thin gold strip along the bar that runs out in 5 s
  bar.fsr = CreateFrame("StatusBar", nil, top)
  bar.fsr:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  bar.fsr:SetStatusBarColor(1, 0.82, 0.2)
  bar.fsr:SetMinMaxValues(0, ns.FSR_SECONDS or 5)
  bar.fsr:Hide()
  -- the three texts (mana numbers, the rule's seconds, the regen) live on their own frames:
  -- they show without the bar and can be dragged ("Move texts freely"). Scaling a frame
  -- changes the text size and keeps the game's font family (a font file set by hand would
  -- lose other alphabets)
  bar.manaBox = CreateTextBox("mana", 120)
  bar.fsrBox = CreateTextBox("fsr", 30)
  bar.regenBox = CreateTextBox("regen", 60)
  bar.text = bar.manaBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  OutlineFont(bar.text, "GameFontHighlightSmall")
  -- seconds left of the rule, small and gold at the end of the bar
  bar.fsrText = bar.fsrBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  OutlineFont(bar.fsrText, "GameFontHighlightSmall")
  bar.fsrText:SetTextColor(1, 0.82, 0.2)
  bar.fsrText:Hide()
  -- current regen ("14.8/s"), under the mana numbers or right of the bar
  bar.regen = bar.regenBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  OutlineFont(bar.regen, "GameFontHighlightSmall", true) -- has letters ("/с", "/秒")
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
-- mana in percent, 0..100. The value is secret, and x100 is not allowed on it; the game's
-- own curve CurveConstants.ScaleTo100 does the scaling inside the engine. Without it the
-- percentage cannot be shown (nil).
local function ManaPercent()
  local curve = CurveConstants and CurveConstants.ScaleTo100
  if not curve then return nil end
  -- the known argument order first, then the other one (no table: this runs every tick)
  local first = powerVariant or 1
  local ok, r = TryPower(first, curve)
  if ok and r ~= nil and (IsSecret(r) or type(r) == "number") then return r end
  ok, r = TryPower(first == 2 and 1 or 2, curve)
  if ok and r ~= nil and (IsSecret(r) or type(r) == "number") then return r end
end
ns.ManaPercent = ManaPercent

-- mana numbers like the game's "Status Text": number / percentage / both / none.
-- Secret values only go into string.format, never into arithmetic or comparisons.
local textFails = 0
local function SetBarText(maxMana)
  local mode = db.manaText or "number"
  if textFails > 20 then return end -- given up until the next loading screen
  local pct = (mode == "percent" or mode == "both") and ManaPercent() or nil
  local ok, text
  if mode == "percent" and pct ~= nil then
    ok, text = pcall(string.format, "%.0f%%", pct)
  elseif mode == "both" and pct ~= nil then
    -- the column has little room beside the bar: two lines there
    ok, text = pcall(string.format, db.vertical and "%.0f%%\n%d / %d" or "%.0f%%   %d / %d",
      pct, UnitPower("player", MANA), maxMana)
  else
    ok, text = pcall(string.format, "%d / %d", UnitPower("player", MANA), maxMana)
  end
  if ok then
    textFails = 0
    bar.text:SetText(text)
  else
    textFails = textFails + 1
    bar.text:SetText("")
    Debug("bartext", "mana text could not be formatted")
  end
end

-- Buttons that are shown (item present and ready) are packed in a row (or a column),
-- so no empty gaps appear for groups you have nothing for. The mana check itself is
-- secret, so a ready item below its threshold still keeps its (invisible) slot.
-- Settings changes call Layout(true); every tick only the set of shown icons is compared
-- auto bar length: room for every group that is switched on and this class can show (at least
-- 3 icons). It does not follow lit icons, so the bar stays still.
function ns.AutoBarLength()
  local size, gap = db.iconSize, db.iconGap or 6
  local slots = 0
  for _, g in ipairs(ns.GROUPS) do
    -- only groups that are switched on; lit icons never change it (the bar stays still)
    if db.enabled[g.key] and ns.ForMyClass(g) and (not g.spells or ns.Spells.AnyKnown()) then
      slots = slots + 1
    end
  end
  slots = math.max(slots, 3)
  return size * slots + gap * (slots - 1)
end

local layoutKey
function ns.Layout(force)
  if not anchor then return end
  local size, gap, vertical = db.iconSize, db.iconGap or 6, db.vertical
  local key, bit = 0, 1
  for _, b in ipairs(buttons) do
    if b.outer:IsShown() then key = key + bit end
    bit = bit * 2
  end
  if key == layoutKey and not force then return end
  layoutKey = key
  local pos, count = 0, 0
  for _, b in ipairs(buttons) do
    b.outer:SetSize(size, size)
    for _, l in ipairs(b.layers) do
      l.glow:SetSize(size * 1.9, size * 1.9)
      l.shine:SetHeight(size * 0.6)
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
    local len = db.barLength and db.barLength > 0 and db.barLength or ns.AutoBarLength()
    local thick = db.barThickness or 14
    if vertical then bar:SetSize(thick, len) else bar:SetSize(len, thick) end
    ns.PositionBar()
  end
end

-- bar under/over the icons, or left/right of the column; the label always sits on top
function ns.PositionBar()
  if not bar or not anchor then return end
  local vertical = db.vertical
  local manaFree = TextFree("mana")
  bar:ClearAllPoints()
  anchor.label:ClearAllPoints()
  bar.manaBox:ClearAllPoints()
  bar.text:ClearAllPoints()
  bar.gloss:ClearAllPoints()
  bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
  if vertical then
    if db.barSide == "right" then
      bar:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    else
      bar:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
    end
    -- the rule's seconds sit above the bar: the frame label (unlocked) goes above them
    local fsrRoom = db.fsr and (math.ceil(14 * (db.fsrScale or 1)) + 4) or 0
    anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 8 + fsrRoom)
    bar.manaBox:SetPoint("TOP", bar, "BOTTOM", 0, -4)
    bar.text:SetPoint("TOP", bar.manaBox, "TOP", 0, 0)
    -- the regen sits under the mana numbers, or under the bar when they were dragged away
    bar.regenBox:ClearAllPoints()
    if manaFree then
      bar.regenBox:SetPoint("TOP", bar, "BOTTOM", 0, -4)
    else
      bar.regenBox:SetPoint("TOP", bar.text, "BOTTOM", 0, -2)
    end
    bar.regen:ClearAllPoints()
    bar.regen:SetPoint("TOP", bar.regenBox, "TOP", 0, 0)
    bar.fsr:ClearAllPoints()
    bar.fsr:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.fsr:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.fsr:SetWidth(3)
    bar.fsr:SetOrientation("VERTICAL")
    bar.fsrBox:ClearAllPoints()
    bar.fsrBox:SetPoint("BOTTOM", bar, "TOP", 0, 6)
    bar.fsrText:ClearAllPoints()
    bar.fsrText:SetPoint("BOTTOM", bar.fsrBox, "BOTTOM", 0, 0)
    bar.gloss:SetPoint("TOPLEFT")
    bar.gloss:SetPoint("BOTTOMLEFT")
    bar.gloss:SetWidth(math.max(1, (db.barThickness or 14) * 0.45))
  else
    -- the mana numbers sit outside the bar, on the side away from the icons: inside, the
    -- markers and the five-second strip made them hard to read
    if db.barPosition == "above" then
      bar:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 6)
      bar.manaBox:SetPoint("BOTTOM", bar, "TOP", 0, 3)
      bar.text:SetPoint("BOTTOM", bar.manaBox, "BOTTOM", 0, 0)
      anchor.label:SetPoint("BOTTOM", manaFree and bar or bar.text, "TOP", 0, 6)
    else
      bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
      bar.manaBox:SetPoint("TOP", bar, "BOTTOM", 0, -3)
      bar.text:SetPoint("TOP", bar.manaBox, "TOP", 0, 0)
      anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
    end
    bar.regenBox:ClearAllPoints()
    bar.regenBox:SetPoint("LEFT", bar, "RIGHT", 6, 0)
    bar.regen:ClearAllPoints()
    bar.regen:SetPoint("LEFT", bar.regenBox, "LEFT", 0, 0)
    bar.fsr:ClearAllPoints()
    bar.fsr:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.fsr:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.fsr:SetHeight(3)
    bar.fsr:SetOrientation("HORIZONTAL")
    -- left of the bar, outside: inside it would cover the mana numbers at large sizes
    bar.fsrBox:ClearAllPoints()
    bar.fsrBox:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    bar.fsrText:ClearAllPoints()
    bar.fsrText:SetPoint("RIGHT", bar.fsrBox, "RIGHT", 0, 0)
    bar.gloss:SetPoint("TOPLEFT")
    bar.gloss:SetPoint("TOPRIGHT")
    bar.gloss:SetHeight(math.max(1, (db.barThickness or 14) * 0.45))
  end
  -- a dragged text keeps its own place (its center stays put when the text size changes)
  local texts = { mana = bar.text, fsr = bar.fsrText, regen = bar.regen }
  for key, field in pairs(TEXT_KEYS) do
    local box, scale = bar[field], TextScale(key)
    box:SetScale(scale)
    if TextFree(key) then
      local p = db.textPoints[key]
      box:ClearAllPoints()
      box:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1] / scale, p[2] / scale)
      texts[key]:ClearAllPoints()
      texts[key]:SetPoint("CENTER", box, "CENTER", 0, 0)
    end
  end
  PaintBar()
end

function ns.ApplyLock()
  local unlocked = not db.locked
  anchor:EnableMouse(unlocked)
  anchor.bg:SetShown(unlocked)
  anchor.label:SetShown(unlocked)
  if bar then
    local drag = unlocked and db.textFree and true or false
    for _, field in pairs(TEXT_KEYS) do
      bar[field]:EnableMouse(drag)
      bar[field].bg:SetShown(drag)
    end
  end
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
  db.textPoints = {} -- the texts go back to the bar
  anchor:ClearAllPoints()
  anchor:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
  PinTopLeft()
  ns.PositionBar()
end

-- icon size, spacing, bar thickness/length and bar text sizes back to the defaults (position stays)
local SIZE_KEYS = { "iconSize", "iconGap", "barThickness", "barLength", "manaScale", "fsrScale", "regenScale" }
function ns.ResetSize()
  for _, k in ipairs(SIZE_KEYS) do db[k] = DEFAULTS[k] end
  ns.Layout(true)
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
local function ClearSweep(l)
  if l.sweep and l.sweepStart then
    if l.sweep.Clear then l.sweep:Clear() else l.sweep:SetCooldown(0, 0) end
    l.sweepStart = nil
  end
end

-- the sweep is set only when a new short cooldown starts, not every tick
local function SweepAt(l, s, d)
  if not l.sweep then return end
  if not s then ClearSweep(l) return end
  if l.sweepStart ~= s then
    l.sweep:SetCooldown(s, d)
    l.sweepStart = s
  end
end

local function ApplySweep(l, id) SweepAt(l, ShortCooldown(id)) end

-- the short lock of a wand shot on spells, taken from the items (see CooldownState)
local function SpellLock()
  if lockStart and lockStart + lockDur > GetTime() then return lockStart, lockDur end
end

local function SetLayer(l, id, n, texture)
  if l.itemID ~= id or not id then
    ClearSweep(l)
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
    l.hi = nil
  end
end

-- "/fmf hold" on one layer: no glow, the word on it (the grey comes from the caller)
local function ShowHeld(b, l, hold)
  if l.held ~= hold then
    l.held = hold
    l.glow:SetShown(not hold)
    l.holdText:SetText(L.holdLabel)
    l.holdText:SetShown(hold)
    l.holdFitW = nil
  end
  if hold then
    -- the word shrinks to fit the icon (RESERVA, small icons); measured at scale 1
    local w = b.outer:GetWidth() or 0
    if w > 0 and l.holdFitW ~= w and l.holdText.SetTextScale then
      l.holdFitW = w
      l.holdText:SetTextScale(1)
      local tw = l.holdText:GetStringWidth() or 0
      l.holdText:SetTextScale(tw > w * 0.9 and w * 0.9 / tw or 1)
    end
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
  ShowHeld(b, l, false) -- the preview shows the icon as it looks when lit
  l:SetAlpha(1)
  l.hi = nil
  l:Show()
  HideLayers(b, 2)
  b.hp:SetAlpha(1)
  b.outer:Show()
end

local function ApplyHpGate(b, hpCost, maxHP)
  if not hpCost then b.hp:SetAlpha(1) return end
  -- max HP unknown: no HP check is possible -> never risk it
  if IsSecret(maxHP) or not maxHP or maxHP <= 0 then
    Debug("hpmax", "max health unreadable - rune hidden")
    b.hp:SetAlpha(0)
    return
  end
  local t = hpCost / maxHP + db.runeMargin
  if b.hpT ~= t then b.hpCurve, b.hpT = HealthCurve(t), t end
  ApplyAlpha(b.hp, HealthColor(b.hpCurve), 0) -- no HP check -> never risk it
end

-- curves are rebuilt only when a threshold changes (lo = nil: band starts at 0%)
local function ApplyBand(l, lo, hi)
  lo = lo or -1
  if l.lo ~= lo or l.hi ~= hi then
    l.curve, l.lo, l.hi = BandCurve(lo >= 0 and lo or nil, hi), lo, hi
  end
  ApplyAlpha(l, PowerColor(l.curve), 0)
end

local groupOK = true -- solo/party/raid filter, evaluated once per tick
local NONE = {}

-- own spells: one slot, the first ready spell; the same mana and health gates as items.
-- Layer IDs of spells are negative so they never match an item ID.
local function UpdateSpellButton(b, maxMana, maxHP)
  local S = ns.Spells
  if not S.AnyKnown() then b.outer:Hide() return end
  local l = b.layers[1]
  if not db.locked then -- positioning preview
    local _, id = S.FirstKnown()
    SetLayer(l, -id, nil, S.Texture(id))
    l:SetAlpha(1); l.hi = nil; l:Show()
    HideLayers(b, 2)
    b.hp:SetAlpha(1)
    b.outer:Show()
    return
  end
  if db.onlyCombat and not InCombatLockdown() then b.outer:Hide() return end
  if not groupOK then b.outer:Hide() return end
  local sp, id = S.Candidate()
  if not sp then b.outer:Hide() return end
  SetLayer(l, -id, nil, S.Texture(id))
  SweepAt(l, SpellLock())
  ApplyBand(l, nil, S.Threshold(sp, maxMana))
  l:Show()
  HideLayers(b, 2)
  ApplyHpGate(b, S.HpCost(sp), maxHP)
  b.outer:Show()
end

local function UpdateButton(i, b, maxMana, maxHP)
  local group = ns.GROUPS[i]
  if not db.enabled[group.key] or not ns.ForMyClass(group) then b.outer:Hide() return end
  if group.spells then return UpdateSpellButton(b, maxMana, maxHP) end
  if not db.locked then ShowPreview(i, b, OwnedItem(i)) return end  -- positioning preview

  if db.onlyCombat and not InCombatLockdown() then b.outer:Hide() return end
  if not groupOK then b.outer:Hide() return end

  -- which items go into the slot, and their mana bands
  local cands
  if db.pickMode == "fit" and CanBand(group) then
    cands = BandCandidates(i)
  else
    local item, n = OwnedItem(i)
    if item and CooldownState(item.id) then
      local single = b.single or { {} }
      b.single = single
      single[1].it, single[1].n = item, n
      cands = single
    else
      cands = NONE
    end
  end
  if #cands == 0 then b.outer:Hide() return end

  local hpCost
  -- on hold: the potion is shown grey with "HOLD" exactly where it would light up
  -- (not on the unlocked frame: that one shows every icon as it looks when lit)
  local hold = held and group.key == "potion" and db.locked
  for k, c in ipairs(cands) do
    local l = b.layers[k]
    SetLayer(l, c.it.id, c.n)
    if hold then l.icon:SetDesaturated(true) end
    ShowHeld(b, l, hold)
    ApplySweep(l, c.it.id)
    -- strongest first: band (threshold of the stronger item, own threshold]
    local lo = k > 1 and Threshold(cands[k - 1].it, maxMana) or nil
    ApplyBand(l, lo, Threshold(c.it, maxMana))
    l:Show()
    if c.it.hpCost then hpCost = math.max(hpCost or 0, c.it.hpCost) end
  end
  HideLayers(b, #cands + 1)
  ApplyHpGate(b, hpCost, maxHP)
  b.outer:Show()
end

local function BarVisible()
  if not db.showBar then return false end
  if not db.locked then return true end
  if not groupOK then return false end
  return not db.onlyCombat or InCombatLockdown()
end

-- one tick mark; it is only moved when its position really changes
local function PlaceTick(t, thr, len, thick, long, vertical)
  if t.thr ~= thr or t.len ~= len or t.long ~= long or t.vertical ~= vertical or t.thick ~= thick then
    t.thr, t.len, t.long, t.vertical, t.thick = thr, len, long, vertical, thick
    -- every mark stays inside the bar (nothing sticks out past the five-second strip);
    -- the mark where the icon lights up is thicker and fully bright, the others thin and dimmer
    local line = long and 3 or 2
    t.front:ClearAllPoints()
    if vertical then
      t.front:SetSize(thick, line)
      t.front:SetPoint("CENTER", bar, "BOTTOM", 0, len * thr)
    else
      t.front:SetSize(line, thick)
      t.front:SetPoint("CENTER", bar, "LEFT", len * thr, 0)
    end
    t.front:SetAlpha(long and 1 or 0.65)
  end
  if not t.front:IsShown() then t.front:Show(); t.back:Show() end
end

local function HideTick(t)
  if t.front:IsShown() then t.front:Hide(); t.back:Hide() end
end

-- seconds left of the five-second rule to show (0: none). Test mode and the unlocked frame
-- preview everything that is switched on: the rule runs in a loop so its strip and
-- seconds can be seen and placed
local function FsrShown()
  local real = db.fsr and ns.FsrLeft and ns.FsrLeft() or 0
  if db.fsr and real == 0 and not db.locked then
    local cycle = ns.FSR_SECONDS or 5
    return cycle - (GetTime() % cycle)
  end
  return real
end

-- the strip runs along the bar, every tick
local function UpdateFsrStrip()
  local left = FsrShown()
  if left > 0 then
    bar.fsr:SetValue(left)
    if not bar.fsr:IsShown() then bar.fsr:Show() end
  elseif bar.fsr:IsShown() then
    bar.fsr:Hide()
  end
end

-- the texts have their own visibility: they also show without the mana bar
local function TextsVisible()
  if not db.locked then return true end
  if not groupOK then return false end
  return not db.onlyCombat or InCombatLockdown()
end

local function ShowBox(box, on)
  if on then
    if not box:IsShown() then box:Show() end
  elseif box:IsShown() then
    box:Hide()
  end
end

-- regen text twice a second (it builds a new string each time) and at once when the rule
-- starts or ends
local regenNext, regenInRule = 0, nil
local function UpdateRegenText(visible)
  local box = bar.regenBox
  if not visible or not db.regenText or not ns.RegenText then
    ShowBox(box, false)
    return
  end
  -- the text shows the casting rate during the rule even when the strip is switched off
  local now, inRule = GetTime(), (ns.FsrLeft and ns.FsrLeft() or 0) > 0
  if box:IsShown() and now < regenNext and inRule == regenInRule then return end
  regenNext, regenInRule = now + 0.5, inRule
  local text, boosted
  text, inRule, boosted = ns.RegenText()
  if text then
    bar.regen:SetText(text)
    -- reduced regen during the rule: gold like the strip; above normal (Spirit Tap,
    -- Evocation, ...): green; normal regen: light blue
    if inRule then
      bar.regen:SetTextColor(1, 0.82, 0.2)
    elseif boosted then
      bar.regen:SetTextColor(0.45, 1, 0.45)
    else
      bar.regen:SetTextColor(0.6, 0.85, 1)
    end
    bar.regen:Show()
    box:Show()
  elseif box:IsShown() then
    box:Hide()
  end
end

-- mana numbers, the rule's seconds and the regen, with or without the bar
local function UpdateTexts(maxMana)
  local visible = TextsVisible()
  local manaOn = visible and db.manaTextOn
  if manaOn then SetBarText(maxMana) end
  ShowBox(bar.manaBox, manaOn)
  local left = visible and FsrShown() or 0
  if left > 0 then
    bar.fsrText:SetText(("%.1f"):format(left))
    if not bar.fsrText:IsShown() then bar.fsrText:Show() end
  elseif bar.fsrText:IsShown() then
    bar.fsrText:Hide()
  end
  ShowBox(bar.fsrBox, left > 0)
  UpdateRegenText(visible)
end

local function UpdateBar(maxMana)
  if not bar then return end
  if not BarVisible() then bar:Hide() return end
  if bar.maxMana ~= maxMana then
    bar:SetMinMaxValues(0, maxMana)
    bar.maxMana = maxMana
  end
  if not pcall(bar.SetValue, bar, UnitPower("player", MANA)) then
    -- unknown mana: show an empty bar rather than a full one
    bar:SetValue(0)
    WarnOnce("barvalue", L.warnPower)
  end
  UpdateFsrStrip()
  local vertical = db.vertical and true or false
  local len = (vertical and bar:GetHeight() or bar:GetWidth()) or 0
  local thick = db.barThickness or 14
  for i, group in ipairs(ns.GROUPS) do
    local ticks = bar.ticks[i]
    local used = 0
    if db.enabled[group.key] and ns.ForMyClass(group) then
      if db.pickMode == "fit" and CanBand(group) then
        -- weakest first: thick mark where the icon lights up, thin marks where a
        -- stronger item becomes the best fit
        local c = BandCandidates(i)
        for k = #c, 1, -1 do
          local thr = Threshold(c[k].it, maxMana)
          if thr > 0 and thr < 1 then
            used = used + 1
            PlaceTick(ticks[used], thr, len, thick, used == 1, vertical)
          end
        end
      else
        local thr = FirstThreshold(i, maxMana)
        if thr and thr > 0 and thr < 1 then
          used = 1
          PlaceTick(ticks[1], thr, len, thick, true, vertical)
        end
      end
    end
    for k = used + 1, #ticks do HideTick(ticks[k]) end
  end
  bar:Show()
end

local function Update()
  candTick = candTick + 1
  -- the frame rect may not be known yet at login: convert old positions on the first tick
  if anchor and not IsPinned(db.point) then PinTopLeft() end
  local maxMana = UnitPowerMax("player", MANA)
  -- dead or a ghost: nothing to drink (the unlocked frame still shows, to place it)
  local okD, dead = pcall(UnitIsDeadOrGhost, "player")
  local isDead = okD and not IsSecret(dead) and dead and db.locked
  if isDead or IsSecret(maxMana) or not maxMana or maxMana <= 0 then
    if not isDead then Debug("maxmana", "max mana unavailable or secret") end
    for _, b in ipairs(buttons) do b.outer:Hide() end
    if bar then
      bar:Hide()
      for _, field in pairs(TEXT_KEYS) do bar[field]:Hide() end
    end
    return
  end
  local maxHP = UnitHealthMax("player")
  ns.Spells.Refresh() -- out of combat: read every spell cooldown, also with hidden icons
  groupOK = GroupAllowed()
  playerLevel = ReadPlayerLevel()
  -- one broken group (odd item, API change) must not blank the others
  for i, b in ipairs(buttons) do
    local ok, err = pcall(UpdateButton, i, b, maxMana, maxHP)
    if not ok then
      b.outer:Hide()
      WarnOnce("update" .. i, L.warnUpdate:format(tostring(err)))
    end
  end
  ns.Layout()
  UpdateBar(maxMana)
  if bar then UpdateTexts(maxMana) end
end

local function SafeUpdate()
  local ok, err = pcall(Update)
  if not ok then WarnOnce("update", L.warnUpdate:format(tostring(err))) end
end

function ns.InvalidateCurves()
  for _, b in ipairs(buttons) do
    b.hpT = nil
    for _, l in ipairs(b.layers) do l.hi = nil end
  end
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
  Print("scale100=%s locked=%s onlyCombat=%s custom=%d", tostring(db.scale100), tostring(db.locked),
    tostring(db.onlyCombat), #db.custom)
end

------------------------------------------------------------------------
-- slash commands
------------------------------------------------------------------------
local RefreshLibrary
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
    ns.SetHold(not held)
    Print(held and L.holdOn or L.holdOff)
    if ns.RefreshOptions then ns.RefreshOptions() end
  elseif cmd == "unlock" then
    db.locked = false; ns.ApplyLock(); Print(L.unlocked)
  elseif cmd == "lock" then
    db.locked = true; ns.ApplyLock(); Print(L.locked)
  elseif cmd == "test" then
    -- test mode and the unlocked frame are one thing now: the same as /fmf unlock
    db.locked = false; ns.ApplyLock(); Print(L.unlocked)
  elseif cmd == "item" and args[2] == "clear" then
    wipe(db.custom); ns.RebuildLists(); RefreshLibrary(); Print(L.itemClear)
  elseif cmd == "item" then
    if not args[2] or not args[3] then Print(L.itemUsage) return end
    ns.AddCustom(args[2], args[3], args[4])
  elseif cmd == "probe" and args[2] == "5sr" then
    if ns.Probe5SR then ns.Probe5SR() end
  elseif cmd == "log" then
    if ns.LogCommand then ns.LogCommand(args[2]) end
  elseif cmd == "scan" then
    if ns.Scan then ns.Scan(args[2]) end
  elseif cmd == "probe" then
    Probe()
  elseif cmd == "debug" then
    db.debug = not db.debug; wipe(warned); Print(db.debug and L.debugOn or L.debugOff)
  elseif cmd == "scale" then
    db.scale100 = not db.scale100
    ns.InvalidateCurves()
    Print("scale100 = %s", tostring(db.scale100))
  elseif cmd == "reset" and args[2] == "size" then
    ns.ResetSize(); Print(L.resetSize)
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

RefreshLibrary = function()
  if ns.RebuildLibrary then ns.RebuildLibrary() end
end

-- returns a whole amount 1..MAX_RESTORE, or nil (also rejects nan and inf)
local function ValidAmount(amount)
  amount = tonumber(amount)
  if not amount or amount ~= amount or amount < 1 or amount > MAX_RESTORE then return nil end
  return math.floor(amount)
end

function ns.AddCustom(id, amount, group)
  id = tonumber(id)
  if not id or id < 1 or id > 2147483647 or id ~= math.floor(id) then
    Print("|cffff4444" .. L.errId .. "|r")
    return false
  end
  amount = ValidAmount(amount)
  if not amount then Print("|cffff4444" .. L.errAmount:format(MAX_RESTORE) .. "|r") return false end
  local ok, err = ValidateItem(id)
  if not ok then Print("|cffff4444" .. err .. "|r") return false end
  local valid, home = false, nil
  for _, g in ipairs(ns.GROUPS) do
    if g.key == group and not g.spells then valid = true end
    for _, it in ipairs(g.items) do if it.id == id then home = g.key end end
  end
  -- no (valid) category given: a known item stays in its own group, others are potions
  if not valid then group = home or "potion" end
  for i = #db.custom, 1, -1 do
    if db.custom[i].id == id then table.remove(db.custom, i) end
  end
  table.insert(db.custom, 1, { id = id, max = amount, group = group })
  ns.RebuildLists()
  RefreshLibrary()
  Print(L.itemAdded, id, amount)
  return true
end

function ns.RemoveCustom(id)
  for i = #db.custom, 1, -1 do
    if db.custom[i].id == id then table.remove(db.custom, i) end
  end
  ns.RebuildLists()
  RefreshLibrary()
end

-- addon compartment (minimap addon menu) entry
function FullManaForever_OnCompartmentClick()
  if ns.ToggleOptions then ns.ToggleOptions() end
end

------------------------------------------------------------------------
-- boot
------------------------------------------------------------------------
local DB_VERSION = 8 -- the last migration below

local freshInstall = false
local function InitDB()
  -- a new install has nothing to migrate
  freshInstall = FullManaForeverDB == nil
  FullManaForeverDB = FullManaForeverDB or { dbVersion = DB_VERSION }
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
    db.macros = nil
    db.dbVersion = 4
  end
  if db.dbVersion < 5 then
    db.showAdvanced = nil
    db.dbVersion = 5
  end
  if db.dbVersion < 6 then
    -- 0.7.1: the separate test mode is gone (the unlocked frame shows everything); a test
    -- mode left on would have no switch to turn it off
    db.test = nil
    db.dbVersion = 6
  end
  if db.dbVersion < 7 then
    -- 0.8.1: the one-time removal of the old FMF_* macros (0.6.6) is gone; drop its flag and
    -- the test-mode key that 0.7.1 test builds left behind
    db.cleanMacros = nil
    db.test = nil
    db.dbVersion = 7
  end
  if db.dbVersion < 8 then
    -- 0.8.2: the mana numbers have their own switch; "none" was the old way to hide them
    if db.manaText == "none" then db.manaTextOn, db.manaText = false, "number" end
    db.dbVersion = 8
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
  elseif event == "PLAYER_ENTERING_WORLD" then
    textFails = 0
  elseif event == "PLAYER_LOGIN" then
    if not db then InitDB() end -- saved variables not delivered (old beta builds)
    ns.RebuildLists() -- player class is known now
    ns.Spells.Rebuild()
    CreateAnchor()
    if ns.InitOptions then
      local ok, err = pcall(ns.InitOptions)
      if not ok then Print(L.warnOptions, tostring(err)) end
    end
    C_Timer.NewTicker(0.1, SafeUpdate)
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- a short tip on the very first login, afterwards one line only when the version changes
    -- (settings from before 0.8.3 have no seenVersion: those players get the version line)
    if freshInstall then
      Print(L.firstRun)
    elseif db.seenVersion ~= ns.VERSION then
      Print(L.loaded, ns.VERSION)
    end
    db.seenVersion = ns.VERSION
  end
end)
