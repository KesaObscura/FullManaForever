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
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:SetScript("OnEvent", function(_, _, unit, _, spellID)
  if unit == "player" and CostsMana(spellID) then fsrUntil = GetTime() + FSR end
end)

-- x5 for a secret value can only happen inside the game: a linear curve evaluated by the
-- engine. If that is not allowed, the regen is shown per second instead of per 5 s.
local times5, times5Broken
local function Times5(v)
  if not IsSecret(v) then return v * 5 end
  if times5Broken or not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then
    return nil
  end
  if not times5 then
    local ok, c = pcall(function()
      local curve = C_CurveUtil.CreateCurve()
      curve:SetType(Enum.LuaCurveType.Linear)
      curve:AddPoint(0, 0)
      curve:AddPoint(10000, 50000)
      return curve
    end)
    if not ok or not c then times5Broken = true return nil end
    times5 = c
  end
  local ok, r = pcall(times5.Evaluate, times5, v)
  if not ok or r == nil then times5Broken = true return nil end
  return r
end

-- text for the mana bar: "3.2s  0 mp5" during the rule, "74 mp5" otherwise.
-- Returns text, inRule (the caller colors it); nil when there is nothing to show.
function ns.RegenText(withRegen, withFsr)
  local left = withFsr and ns.FsrLeft() or 0
  local value
  if withRegen and GetPowerRegen then
    local ok, base, casting = pcall(GetPowerRegen)
    if ok then
      -- while the rule runs, regen is the casting rate (the game knows about talents and
      -- Innervate, so they are included)
      if ns.FsrLeft() > 0 then value = casting else value = base end
    end
  end
  local text, ok
  if value ~= nil then
    local mp5 = Times5(value)
    if mp5 ~= nil then
      if left > 0 then ok, text = pcall(string.format, "%.1fs  %.0f mp5", left, mp5)
      else ok, text = pcall(string.format, "%.0f mp5", mp5) end
    else
      if left > 0 then ok, text = pcall(string.format, "%.1fs  %.1f/s", left, value)
      else ok, text = pcall(string.format, "%.1f/s", value) end
    end
    if not ok then text = nil end
  end
  if not text and left > 0 then text = ("%.1fs"):format(left) end
  return text, left > 0
end

-- for the diagnostics log: did x5 on a secret value work in this session?
function ns.Times5State()
  if times5Broken then return "broken" end
  return times5 and "ok" or "untried"
end

-- for tests and the bar strip
ns.FSR_SECONDS = FSR
