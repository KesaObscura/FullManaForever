-- Full Mana Forever - five-second rule and mana regen for the mana bar (0.7.0).
-- Facts from in-game logs (Forever beta): regen is continuous (no 2 s ticks); a spell that
-- costs mana reduces regen for 5 s to the "casting" rate (0 without talents, 50 % with
-- Spirit Tap, 100 % with Innervate). The player's casts and their mana costs are readable
-- in combat; GetPowerRegen is readable out of combat and SECRET in combat. A secret value
-- may be shown as text, never compared or used in arithmetic.

local _, ns = ...
local FSR = 5           -- seconds of the five-second rule
local MANA = 0          -- Enum.PowerType.Mana
local fsrUntil = 0
-- regen above normal ("boosted", shown green): out of combat the value is compared with the
-- lowest regen of the last 5 minutes out of combat (0.9.3; before: the lowest since the last
-- level-up or gear change, so an hour-long group buff such as Blessing of Wisdom or Mana
-- Spring kept the regen green all the time). Short raises (drinking, Spirit Tap) stay green,
-- a buff that is kept up becomes the normal rate after 5 minutes. Only time out of combat
-- counts: after a long fight the normal rate from before it is kept, so drinking right after
-- it is green. In combat the value is secret, so only own spells that raise regen count, for
-- their known duration
local BOOST_RATIO = 1.1       -- 10 % above normal, so small rounding never turns it green
local BOOST_SPELLS = {        -- [spell] = seconds of raised regen (own casts only)
  [12051] = 8,                -- Evocation (channel)
  [1259705] = 30,             -- Read Leyline (30 s without a leyline nearby, else 15 min; game text 17 Oct)
}
-- the lowest regen per 30 s, for the last 10 such parts with a sample (5 minutes out of combat)
local BUCKET, KEEP = 30, 10
-- { { k = part number, v = lowest regen with the mana buffs, b = lowest regen the game reports }, ... }
local buckets = {}            -- oldest first
local function Learn(total, base, now)
  local k = math.floor(now / BUCKET)
  local last = buckets[#buckets]
  if last and last.k == k then
    if total < last.v then last.v = total end
    if base < last.b then last.b = base end
  else
    buckets[#buckets + 1] = { k = k, v = total, b = base }
    if #buckets > KEEP then table.remove(buckets, 1) end
  end
end
local function Normal()
  local m
  for _, b in ipairs(buckets) do if not m or b.v < m then m = b.v end end
  return m
end
-- the same for the game's own number, without the mana buffs
local function NormalBase()
  local m
  for _, b in ipairs(buckets) do if not m or b.b < m then m = b.b end end
  return m
end
local boostUntil = 0
local SICKNESS = 15007        -- Resurrection Sickness: -75 % attributes for up to 10 min

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

-- is the regen lowered for a while (Resurrection Sickness: -75 % Spirit and Intellect)?
-- Such a value must not become the normal regen, or normal regen turns green once the
-- debuff ends (0.8.9). Only a big cut counts: gear and small debuffs with a few points
-- less Spirit stay part of the normal regen. The sickness takes 75 % of the BASE stat
-- (in game: Spirit 38 = base 48 + 26 from buffs - 36), so the cut is compared with the base.
local LOWERED = 0.5           -- at least half of the base stat taken away
local LOWERED_STATS = { 4, 5 } -- 4 Intellect, 5 Spirit
local function Lowered()
  if UnitStat then
    for _, stat in ipairs(LOWERED_STATS) do
      local ok, _, eff, pos, neg = pcall(UnitStat, "player", stat)
      if ok and not IsSecret(eff) and not IsSecret(pos) and not IsSecret(neg)
        and type(eff) == "number" and type(pos) == "number" and type(neg) == "number"
        and neg < 0 and -neg >= (eff - pos - neg) * LOWERED then
        return true
      end
    end
  end
  local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
  if get then
    local ok, aura = pcall(get, SICKNESS)
    if ok and not IsSecret(aura) and aura ~= nil then return true end
  end
  return false
end

-- does this spell cost mana right now? (cost includes reductions such as Eureka)
local function CostsMana(id)
  if id == nil or IsSecret(id) then return false end
  local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
  if not getCost then return false end
  local ok, list = pcall(getCost, id)
  if not ok or type(list) ~= "table" then return false end
  for _, c in ipairs(list) do
    if not IsSecret(c.type) and not IsSecret(c.cost) and c.type == MANA and (c.cost or 0) > 0 then
      return true
    end
  end
  return false
end

-- Mana buffs whose mana comes in on top of the regen the game reports. Mana per second by spell
-- ID, from the game's own texts; both keep running within the five-second rule.
-- Blessing of Wisdom: 12-40 mana every 5 s, one hour.
local WISDOM = {
  [19742] = 12 / 5, [19850] = 18 / 5, [19852] = 24 / 5, [19853] = 30 / 5, [19854] = 36 / 5,
  [25290] = 40 / 5, [25894] = 36 / 5, [25918] = 40 / 5,                -- the last two: Greater
}
-- Mana Spring Totem: the buff on the player while near the totem, 4-10 mana every 2 s, no end
-- time (it comes and goes with the distance to the totem)
local SPRING = { [5677] = 4 / 2, [10491] = 6 / 2, [10493] = 8 / 2, [10494] = 10 / 2 }
local wisdom, wisdomUntil, spring = 0, 0, 0
-- The buffs are read out of combat only: in a fight the game does not tell which buff came or
-- went, and says "no such buff" for one that is there. The blessing lasts an hour, so what was
-- known before the fight is kept until it runs out; the totem buff depends on where the player
-- and the totem are, so in a fight it is not counted. Both are read again when the fight ends.
local function AurasHidden()
  if InCombatLockdown and InCombatLockdown() then return true end
  local f = C_Secrets and C_Secrets.ShouldAurasBeSecret
  if f then
    local ok, v = pcall(f)
    if not ok or IsSecret(v) or v then return true end
  end
  return false
end
-- the strongest of the given buffs on the player: per second and its end time; nil if unreadable
local function Strongest(get, list)
  local best, ends = 0, 0
  for id, perSec in pairs(list) do
    local ok, a = pcall(get, id)
    if not ok or IsSecret(a) then return nil end
    if type(a) == "table" and perSec > best then
      local exp = a.expirationTime
      if IsSecret(exp) then return nil end
      best, ends = perSec, (type(exp) == "number" and exp > 0) and exp or math.huge
    end
  end
  return best, ends
end
-- recheckAt: one more look shortly after a fight or a loading screen, in case the first one came
-- too early; settleUntil: until then a change of the buffs starts the learning of the normal
-- regen again (the buffs may show up a moment after the regen at login, which would look like
-- a raise)
local recheckAt, settleUntil = nil, 0
-- true when the buffs were read
local function ScanBuffs()
  local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
  if not get or AurasHidden() then return false end
  local w, wEnds = Strongest(get, WISDOM)
  local s = Strongest(get, SPRING)
  if w == nil or s == nil then return false end
  if (w ~= wisdom or s ~= spring) and GetTime() < settleUntil then wipe(buckets) end
  wisdom, wisdomUntil, spring = w, wEnds, s
  return true
end
-- mana per second from such buffs right now (0 without one)
function ns.BuffRegen()
  local now = GetTime()
  if recheckAt and now >= recheckAt then
    recheckAt = nil
    -- still not readable out of combat: look again in a second
    if not ScanBuffs() and not (InCombatLockdown and InCombatLockdown()) then recheckAt = now + 1 end
  end
  local n = 0
  if wisdom > 0 and now < wisdomUntil then n = n + wisdom end
  if spring > 0 and not AurasHidden() then n = n + spring end
  return n
end
local auraFrame = CreateFrame("Frame")
if auraFrame.RegisterUnitEvent then
  auraFrame:RegisterUnitEvent("UNIT_AURA", "player")
else
  auraFrame:RegisterEvent("UNIT_AURA")
end
auraFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
auraFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
auraFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- the last look before a fight
auraFrame:RegisterEvent("PLAYER_DEAD")           -- death takes the buffs
-- the drink found among the buffs (ns.DrinkLeft); looked for again only after the buffs changed
local drinkDirty, drinkExp = true, nil
auraFrame:SetScript("OnEvent", function(_, event, unit)
  if event == "UNIT_AURA" and unit ~= "player" then return end
  drinkDirty = true
  local now = GetTime()
  if event == "PLAYER_DEAD" then
    wisdom, wisdomUntil, spring = 0, 0, 0
    recheckAt = now + 1
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    recheckAt, settleUntil = now + 1, now + 5
  elseif event == "PLAYER_REGEN_ENABLED" then
    recheckAt = now + 1
  end
  ScanBuffs()
end)

-- In a fight the game itself shows a label of ours next to the regen for as long as one of these
-- buffs is on the player: "+2.4" for the blessing, "+2.0" for the totem, side by side. The addon
-- only hands the labels over (out of combat); it never learns which of them show.
local plus = {}               -- host: our frame the labels sit in; live: the game shows them
-- { { perSec, { [id] = true, ... } }, ... } weakest first, one entry per amount
local function ByAmount(list)
  local seen, out = {}, {}
  for id, perSec in pairs(list) do
    local e = seen[perSec]
    if not e then e = { perSec, {} }; seen[perSec] = e; out[#out + 1] = e end
    e[2][id] = true
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end
-- parent: the box of the regen text; font: its font. True when the labels are in the game's hands.
function ns.BuffPlusCreate(parent, font)
  if plus.host or plus.failed then return plus.live or false end
  if InCombatLockdown and InCombatLockdown() then return false end -- only out of combat
  local host = CreateFrame("Frame", nil, parent)
  host:SetSize(1, 12)
  host:SetAlpha(0)
  plus.host = host
  local ok = pcall(function()
    local c = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
    c:SetPoint("LEFT", host, "LEFT", 0, 0)
    c:SetUnit("player")
    c:SetEnabled(true)
    local n = 0
    for _, list in ipairs({ WISDOM, SPRING }) do
      for _, e in ipairs(ByAmount(list)) do
        n = n + 1
        local label = ("+%.1f"):format(e[1])
        c:AddAuraGroup("fmf" .. n, "HELPFUL", {
          maxFrameCount = 1,
          candidateFilters = { includeSpellIDs = e[2] },
          layout = { groupSpacing = 3 },
          initializeFrame = function(b)
            local fs = b:CreateFontString(nil, "OVERLAY")
            if font then fs:SetFontObject(font) end
            -- a dark outline and shadow, so the white reads on any ground
            local file, size = fs:GetFont()
            if file then fs:SetFont(file, size, "OUTLINE") end
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(1, -1)
            fs:SetTextColor(1, 1, 1)
            fs:SetPoint("CENTER")
            fs:SetText(label)
            b:SetSize(math.ceil(fs:GetStringWidth() or 24) + 1, 12)
            if b.EnableMouse then b:EnableMouse(false) end
          end,
        })
      end
    end
    plus.box = c
  end)
  if not ok then plus.failed = true; host:Hide() return false end
  plus.live = true
  return true
end
-- where the labels start: region and its point, our point, offsets (the regen text and its side)
function ns.BuffPlusPlace(point, region, relPoint, dx, dy)
  local host = plus.host
  if not host then return end
  host:ClearAllPoints()
  host:SetPoint(point, region, relPoint, dx, dy)
end
-- shown in a fight (the summed number takes over outside one)
function ns.BuffPlusShow(on)
  if plus.host and plus.live then plus.host:SetAlpha(on and 1 or 0) end
end
function ns.BuffPlusLive() return plus.live or false end

-- seconds left of the five-second rule (0 = regen runs at the normal rate)
function ns.FsrLeft()
  local left = fsrUntil - GetTime()
  return left > 0 and left or 0
end

local frame = CreateFrame("Frame")
-- only the player's casts: in a raid every unit's casts would wake the handler
if frame.RegisterUnitEvent then
  frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
  frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
-- a new level or other gear changes the normal regen: it is learned again
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
  if event ~= "UNIT_SPELLCAST_SUCCEEDED" then wipe(buckets) return end
  if unit ~= "player" then return end
  if CostsMana(spellID) then fsrUntil = GetTime() + FSR end
  local boost = not IsSecret(spellID) and BOOST_SPELLS[spellID]
  if boost then boostUntil = math.max(boostUntil, GetTime() + boost) end
end)

-- text for the mana bar: the regen that is running right now, per second ("14.8/s").
-- During the rule that is the casting rate: 0 without talents, more with talents,
-- Innervate or gear (the game includes all of it). In combat the value is secret: it can
-- only be formatted, never compared or multiplied, which is why there is no mp5 here.
-- Returns text, inRule, boosted, lowered; nil when there is nothing to show.
-- the regen of mana itself: GetPowerRegen gives the current power type, energy in cat form
-- and rage in bear form, which showed as mana regen and was even learned as "normal" (0.9.2)
local MANA = 0
-- With mana as the power type the checked GetPowerRegen stays in use (verified in Forever);
-- in another form the mana regen comes from GetPowerRegenForPowerType, or is not shown.
local function ManaRegen()
  local other = false
  if UnitPowerType then
    local okT, ptype = pcall(UnitPowerType, "player")
    other = okT and not IsSecret(ptype) and ptype ~= nil and ptype ~= MANA
  end
  if other then
    if not GetPowerRegenForPowerType then return false end
    return pcall(GetPowerRegenForPowerType, MANA)
  end
  if not GetPowerRegen then return false end
  return pcall(GetPowerRegen)
end

-- seconds of drinking left, out of combat (auras are readable there), and the normal rate that
-- follows (the lowest regen of the last minutes); nil when not drinking. The drink is found by
-- the names the game gives the drink spells (430 "Drink" and 1249914 "Nutritious Drink" in the
-- client's language), so new drink IDs with these names match too, or by the spell IDs below:
-- 430, 431, 432, 1133, 1135, 1137, 22734 (seen in game 10 Nov); the Forever teas (Nutritious
-- Drink 1249914-1249925), rations, biscuits and other drinks with mana (scan 11 Nov).
local DRINK_IDS = {}
for _, id in ipairs({ 430, 431, 432, 833, 1133, 1135, 1137, 2639, 18140, 22734, 23540, 23541,
  23542, 23692, 23698, 24384, 24409, 24410, 24411, 25692, 25693, 29029, 461632, 1226814,
  1269354, 1290859, 1290860, 1290861, 1291782 }) do DRINK_IDS[id] = true end
for id = 1249914, 1249925 do DRINK_IDS[id] = true end
local DRINK_NAME_IDS = { 430, 1249914 }
local drinkNames
-- the end time of a drink among the buffs, nil without one; false when the buffs could not be read
local function FindDrink(get, now)
  if (drinkNames == nil or next(drinkNames) == nil) and C_Spell and C_Spell.GetSpellName then
    drinkNames = {}
    for _, sid in ipairs(DRINK_NAME_IDS) do
      local ok, n = pcall(C_Spell.GetSpellName, sid)
      if ok and type(n) == "string" and not IsSecret(n) then drinkNames[n] = true end
    end
  end
  for i = 1, 40 do
    local ok, a = pcall(get, "player", i, "HELPFUL")
    if not ok or IsSecret(a) then return false end
    if a == nil then return nil end
    local id, name, exp = a.spellId, a.name, a.expirationTime
    if IsSecret(id) or IsSecret(name) or IsSecret(exp) then return false end
    if (DRINK_IDS[id] or (drinkNames and type(name) == "string" and drinkNames[name]))
      and type(exp) == "number" and exp > now then
      return exp
    end
  end
  return nil
end
-- The buffs are read once after they changed (every buff change brings an aura event), not on
-- every update: each buff read makes a new table, ten times a second with many buffs.
function ns.DrinkLeft()
  if InCombatLockdown and InCombatLockdown() then drinkDirty = true return nil end
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return nil end
  local now = GetTime()
  if drinkDirty then
    local exp = FindDrink(get, now)
    if exp == false then return nil end -- not readable now: tried again next time
    drinkExp, drinkDirty = exp, false
  end
  if not drinkExp or drinkExp <= now then return nil end
  -- after the drink: the lowest regen the game reported lately, plus the mana buffs of now
  local normal = NormalBase()
  return drinkExp - now, normal and normal + ns.BuffRegen() or nil
end

-- base and casting rate as plain numbers (Blessing of Wisdom and Mana Spring included), nil while they are
-- secret (in combat): for the time to full mana (0.9.7), which only shows out of combat
function ns.RegenRates()
  local ok, base, casting = ManaRegen()
  if not ok or IsSecret(base) or type(base) ~= "number" then return nil end
  if IsSecret(casting) or type(casting) ~= "number" then casting = 0 end
  local extra = ns.BuffRegen()
  return base + extra, casting + extra
end

local patUnit, patPlain, patPlus
function ns.RegenText()
  local ok, base, casting = ManaRegen()
  if not ok then return nil end
  local inRule = ns.FsrLeft() > 0
  local value
  if inRule then value = casting else value = base end
  if not IsSecret(value) and value == nil then return nil end
  -- Blessing of Wisdom and Mana Spring Totem on top: added to a plain value, shown as a white
  -- "+3.6" next to a secret one
  local extra = ns.BuffRegen()
  -- the unit is part of the pattern; "%" in a unit would have to be escaped
  if patUnit ~= ns.L.regenUnit then
    patUnit = ns.L.regenUnit
    patPlain, patPlus = "%.1f" .. patUnit, "%.1f|cffffffff+%.1f|r" .. patUnit
  end
  local okF, text
  if extra > 0 and IsSecret(value) and not plus.live then
    -- no labels from the game: what was known before the fight, as a white "+3.6"
    okF, text = pcall(string.format, patPlus, value, extra)
  elseif IsSecret(value) then
    okF, text = pcall(string.format, patPlain, value)
  else
    if extra > 0 and type(value) == "number" then value = value + extra end
    okF, text = pcall(string.format, patPlain, value)
  end
  if not okF then return nil end
  local boosted = GetTime() < boostUntil
  local low = Lowered()
  if not inRule and not IsSecret(base) and type(base) == "number" and base > 0 then
    local total = base + extra
    if not low then Learn(total, base, GetTime()) end
    local normal = Normal()
    boosted = boosted or (normal ~= nil and total > normal * BOOST_RATIO + 0.05)
  end
  -- below normal for a while (Resurrection Sickness): red with a down arrow (0.8.9)
  local lowered = not inRule and not boosted and low
  return text, inRule, boosted, lowered
end

-- for tests and the bar strip
ns.FSR_SECONDS = FSR
