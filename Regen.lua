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
-- A failure is retried after a while (right after login values can be briefly secret);
-- the last outcome is kept for the diagnostics log.
local times5, times5State, times5Retry = nil, "untried", 0
local RETRY = 10

local function Short(err) return tostring(err):sub(1, 60) end

local function Times5(v)
  if not IsSecret(v) then return v * 5 end
  if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then
    times5State = "no-api"
    return nil
  end
  local now = GetTime()
  if times5State ~= "ok" and times5State ~= "untried" and now < times5Retry then return nil end
  if not times5 then
    local ok, c = pcall(function()
      local curve = C_CurveUtil.CreateCurve()
      curve:SetType(Enum.LuaCurveType.Linear)
      curve:AddPoint(0, 0)
      curve:AddPoint(10000, 50000)
      return curve
    end)
    if not ok or not c then
      times5State, times5Retry = "create-error " .. Short(c), now + RETRY
      return nil
    end
    times5 = c
  end
  local ok, r = pcall(times5.Evaluate, times5, v)
  if not ok or r == nil then
    times5State, times5Retry = "eval-error " .. Short(r), now + RETRY
    return nil
  end
  times5State = "ok"
  return r
end

-- text for the mana bar. Outside the rule: "74 mp5". During the rule both rates,
-- "3.2s  0 -> 74 mp5": what runs while casting (0 without talents, half with Spirit Tap,
-- all with Innervate) and the normal rate you go back to. In combat the values are secret:
-- they can only be formatted, and per second when x5 is not possible.
-- Returns text, inRule; nil when there is nothing to show.
function ns.RegenText(withRegen, withFsr)
  local left = withFsr and ns.FsrLeft() or 0
  local base, casting
  if withRegen and GetPowerRegen then
    local ok, b, c = pcall(GetPowerRegen)
    if ok then base, casting = b, c end
  end
  local text, ok
  if base ~= nil then
    local b5 = Times5(base)
    local c5 = left > 0 and casting ~= nil and Times5(casting)
    if b5 ~= nil and (left == 0 or c5) then
      if left > 0 then ok, text = pcall(string.format, "%.1fs  %.0f -> %.0f mp5", left, c5, b5)
      else ok, text = pcall(string.format, "%.0f mp5", b5) end
    else
      if left > 0 and casting ~= nil then
        ok, text = pcall(string.format, "%.1fs  %.1f -> %.1f/s", left, casting, base)
      else
        ok, text = pcall(string.format, "%.1f/s", base)
      end
    end
    if not ok then text = nil end
  end
  if not text and left > 0 then text = ("%.1fs"):format(left) end
  return text, left > 0
end

-- for the diagnostics log: did x5 on a secret value work in this session?
function ns.Times5State() return times5State end

-- for tests and the bar strip
ns.FSR_SECONDS = FSR
