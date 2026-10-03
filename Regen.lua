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
frame:SetScript("OnEvent", function(_, _, unit, _, spellID)
  if unit == "player" and CostsMana(spellID) then fsrUntil = GetTime() + FSR end
end)

-- text for the mana bar: the regen that is running right now, per second ("14.8/s").
-- During the rule that is the casting rate: 0 without talents, more with talents,
-- Innervate or gear (the game includes all of it). In combat the value is secret: it can
-- only be formatted, never compared or multiplied, which is why there is no mp5 here.
-- Returns text, inRule; nil when there is nothing to show.
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
  return text, inRule
end

-- for tests and the bar strip
ns.FSR_SECONDS = FSR
