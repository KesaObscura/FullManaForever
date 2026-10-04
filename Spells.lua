-- Full Mana Forever - own spells that give or save mana (0.8.0).
-- Facts from /fmf scan in Forever: own casts and their spell IDs are readable in combat;
-- spell cooldowns are readable out of combat and SECRET in combat; GetSpellBaseCooldown
-- works for every spell. So the cooldown is read exactly out of combat, and in combat it
-- is counted from the player's own cast. A spell is never shown as ready too early: if in
-- doubt (a secret value, no data) it counts as not ready.

local _, ns = ...
local S = {}
ns.Spells = S

local GCD = 1.6            -- a cooldown this short is the global cooldown, not the spell's
local known = {}           -- [entry] = the player's spell ID (highest rank in the book)
local byID = {}            -- [spell ID] = entry, for the player's casts
local readyAt = {}         -- [entry] = GetTime() when the spell is ready again
local amount = {}          -- [entry] = mana it gives (fit spells, from the description)
local dirty = true

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

local function SpellName(id)
  if not (C_Spell and C_Spell.GetSpellName) then return nil end
  local ok, n = pcall(C_Spell.GetSpellName, id)
  if ok and n ~= nil and not IsSecret(n) then return n end
end

-- the player's spell book: name -> highest rank (the book lists ranks in ascending order)
local function BookByName(want)
  local found = {}
  local book = C_SpellBook
  if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo
    and book.GetSpellBookItemInfo) then
    return found
  end
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  for i = 1, book.GetNumSpellBookSkillLines() do
    local line = book.GetSpellBookSkillLineInfo(i)
    if line then
      for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
        local it = book.GetSpellBookItemInfo(j, bank)
        if it and it.spellID and it.name and want[it.name] and not it.isPassive then
          found[it.name] = it.spellID
        end
      end
    end
  end
  return found
end

-- first whole number in the description ("Converts 499 Health into 499 Mana")
local function AmountFromText(id)
  if not (C_Spell and C_Spell.GetSpellDescription) then return nil end
  local ok, d = pcall(C_Spell.GetSpellDescription, id)
  if not ok or type(d) ~= "string" or IsSecret(d) then return nil end
  local n = tonumber(d:match("(%d+)"))
  if n and n > 0 then return n end
end

-- which of the spells does this character have (out of combat; the book may change in combat)
function S.Rebuild()
  if InCombatLockdown() then dirty = true return end
  wipe(known); wipe(byID); wipe(amount)
  local want = {}
  for _, sp in ipairs(ns.SPELLS) do
    if ns.ForMyClass(sp) then
      local name = SpellName(sp.id)
      if name then want[name] = sp end
    end
  end
  local found = BookByName(want)
  for name, sp in pairs(want) do
    local id = found[name]
    if not id and IsPlayerSpell and IsPlayerSpell(sp.id) then id = sp.id end
    if id then
      known[sp], byID[id] = id, sp
      if sp.fit then amount[sp] = AmountFromText(id) end
    end
  end
  dirty = false
end

function S.AnyKnown()
  return next(known) ~= nil
end

-- the game's cooldown when it can be read (out of combat), else what we counted
local function ReadCooldown(id)
  local start, dur
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or IsSecret(cd) or type(cd) ~= "table" then return false end
    start, dur = cd.startTime, cd.duration
  elseif GetSpellCooldown then
    local ok, s, d = pcall(GetSpellCooldown, id)
    if not ok then return false end
    start, dur = s, d
  else
    return false
  end
  if IsSecret(start) or IsSecret(dur) or start == nil or dur == nil then return false end
  return true, start, dur
end

-- ready, secondsLeft
function S.Ready(sp)
  local id = known[sp]
  if not id then return false, 0 end
  local readable, start, dur = ReadCooldown(id)
  if readable then
    if dur > GCD and start > 0 then readyAt[sp] = start + dur else readyAt[sp] = nil end
  end
  local r = readyAt[sp]
  local left = r and r - GetTime() or 0
  if left <= 0.05 then return true, 0 end
  return false, left
end

-- the first spell to show now (known, switched on, ready), and its ID
function S.Candidate()
  for _, sp in ipairs(ns.SPELLS) do
    if known[sp] and S.Ready(sp) then return sp, known[sp] end
  end
end

-- the first known spell (preview, status, bar tick), and its ID
function S.FirstKnown()
  for _, sp in ipairs(ns.SPELLS) do
    if known[sp] then return sp, known[sp] end
  end
end

-- mana% at or below which the icon lights up
function S.Threshold(sp, maxMana)
  local a = sp.fit and amount[sp]
  if a and maxMana and maxMana > 0 then return math.max(0, 1 - a / maxMana) end
  return ns.db.spellThreshold or 0.5
end

-- health the spell costs (Life Tap), for the same health check as the runes
function S.HpCost(sp)
  return sp.fit and amount[sp] or nil
end

function S.Texture(id)
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, t = pcall(C_Spell.GetSpellTexture, id)
    if ok and t and not IsSecret(t) then return t end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

S.Name = SpellName

-- the player's own casts start the count in combat (the game's base cooldown, else ours)
local function OnCast(id)
  if id == nil or IsSecret(id) then return end
  local sp = byID[id]
  if not sp then return end
  local cd = sp.cd or 0
  if GetSpellBaseCooldown then
    local ok, ms = pcall(GetSpellBaseCooldown, id)
    if ok and ms and not IsSecret(ms) and ms > 0 then cd = ms / 1000 end
  end
  if cd > GCD then readyAt[sp] = GetTime() + cd end
end

local frame = CreateFrame("Frame")
if frame.RegisterUnitEvent then
  frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
  frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if unit == "player" then OnCast(spellID) end
  elseif event == "SPELLS_CHANGED" or (event == "PLAYER_REGEN_ENABLED" and dirty) then
    if ns.db then S.Rebuild() end
  end
end)
