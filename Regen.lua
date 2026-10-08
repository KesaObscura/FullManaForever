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
-- lowest normal regen seen since the last level-up or gear change; in combat the value is
-- secret, so only own spells that raise regen count, for their known duration
local BOOST_RATIO = 1.1       -- 10 % above normal, so small rounding never turns it green
local BOOST_SPELLS = {        -- [spell] = seconds of raised regen (own casts only)
  [12051] = 8,                -- Evocation (channel)
  [1259705] = 15,             -- Ley Line reading (15 s without a ley line nearby, else 15 min)
}
local baseline
local boostUntil = 0

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

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
  if event ~= "UNIT_SPELLCAST_SUCCEEDED" then baseline = nil return end
  if unit ~= "player" then return end
  if CostsMana(spellID) then fsrUntil = GetTime() + FSR end
  local boost = not IsSecret(spellID) and BOOST_SPELLS[spellID]
  if boost then boostUntil = math.max(boostUntil, GetTime() + boost) end
end)

-- text for the mana bar: the regen that is running right now, per second ("14.8/s").
-- During the rule that is the casting rate: 0 without talents, more with talents,
-- Innervate or gear (the game includes all of it). In combat the value is secret: it can
-- only be formatted, never compared or multiplied, which is why there is no mp5 here.
-- Returns text, inRule, boosted; nil when there is nothing to show.
function ns.RegenText()
  if not GetPowerRegen then return nil end
  local ok, base, casting = pcall(GetPowerRegen)
  if not ok then return nil end
  local inRule = ns.FsrLeft() > 0
  local value
  if inRule then value = casting else value = base end
  if value == nil then return nil end
  -- the unit is part of the pattern; "%" in a unit would have to be escaped
  local okF, text = pcall(string.format, "%.1f" .. ns.L.regenUnit, value)
  if not okF then return nil end
  local boosted = GetTime() < boostUntil
  if not inRule and not IsSecret(base) and type(base) == "number" and base > 0 then
    if not baseline or base < baseline then baseline = base end
    boosted = boosted or base > baseline * BOOST_RATIO + 0.05
  end
  return text, inRule, boosted
end

-- for tests and the bar strip
ns.FSR_SECONDS = FSR
