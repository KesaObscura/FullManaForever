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
-- a cooldown read from the game this short is a wand shot's lock on all spells (and items),
-- not the spell's own: mana spells have minutes. The icon shows it as a sweep (Core.lua)
local SHORT = 5
local MANA = 0
local NEVER = math.huge    -- readyAt while the cooldown waits (Inner Focus until it is used)
local known = {}           -- [entry] = the player's spell ID (highest rank in the book)
local byID = {}            -- [spell ID] = entry, every rank in the book (ranks share a cooldown)
local readyAt = {}         -- [entry] = GetTime() when the spell is ready again
local seen = {}            -- [entry] = true once its cooldown was read out of combat
local amount = {}          -- [entry] = mana it gives (fit spells, from the description)
local texture = {}         -- [spell ID] = icon
local waiting              -- entry whose cooldown starts with the next spell (Inner Focus)
local dirty = true

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

local function SpellName(id)
  if not (C_Spell and C_Spell.GetSpellName) then return nil end
  local ok, n = pcall(C_Spell.GetSpellName, id)
  if ok and n ~= nil and not IsSecret(n) then return n end
end

-- the player's spell book: name -> list of ranks, highest last (the book lists them in
-- ascending order). Spells of later levels, if the book ever lists them, do not count.
local function BookByName(want)
  local found = {}
  local future = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
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
        if it and it.spellID and it.name and want[it.name] and not it.isPassive
          and not (future and it.itemType == future) then
          local ranks = found[it.name] or {}
          found[it.name] = ranks
          ranks[#ranks + 1] = it.spellID
        end
      end
    end
  end
  return found
end

-- first whole number in the description ("Converts 499 Health into 499 Mana"); nil while
-- the text is not loaded yet (asked for, read again later)
local function AmountFromText(id)
  if not (C_Spell and C_Spell.GetSpellDescription) then return nil end
  if C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
  local ok, d = pcall(C_Spell.GetSpellDescription, id)
  if not ok or type(d) ~= "string" or IsSecret(d) then return nil end
  local n = tonumber(d:match("(%d+)"))
  if n and n > 0 then return n end
end

-- which of the spells does this character have (out of combat; the book may change in combat)
function S.Rebuild()
  if InCombatLockdown() then dirty = true return end
  wipe(known); wipe(byID); wipe(amount)
  waiting = nil
  local want = {}
  for _, sp in ipairs(ns.SPELLS) do
    if ns.ForMyClass(sp) then
      local name = SpellName(sp.id)
      if name then want[name] = sp end
    end
  end
  local found = BookByName(want)
  for name, sp in pairs(want) do
    local ranks = found[name]
    local id = ranks and ranks[#ranks]
    if not id and IsPlayerSpell and IsPlayerSpell(sp.id) then id = sp.id end
    if id then
      known[sp], byID[id] = id, sp
      for _, r in ipairs(ranks or {}) do byID[r] = sp end
      if sp.fit then amount[sp] = AmountFromText(id) end
    end
  end
  dirty = false
end

function S.AnyKnown()
  return next(known) ~= nil
end

-- the game's cooldown when it can be read (out of combat), else what we counted.
-- enabled false: the cooldown waits (Inner Focus while its buff is up)
local function ReadCooldown(id)
  local start, dur, enabled
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or IsSecret(cd) or type(cd) ~= "table" then return false end
    start, dur, enabled = cd.startTime, cd.duration, cd.isEnabled
    if IsSecret(enabled) then return false end
  elseif GetSpellCooldown then
    local ok, s, d = pcall(GetSpellCooldown, id)
    if not ok then return false end
    start, dur = s, d
  else
    return false
  end
  if IsSecret(start) or IsSecret(dur) or start == nil or dur == nil then return false end
  return true, start, dur, enabled
end

-- ready, secondsLeft (nil: not known when it is ready). In combat the game's cooldown is
-- secret and not even asked for; a spell whose cooldown was never read counts as not ready.
function S.Ready(sp)
  local id = known[sp]
  if not id then return false, 0 end
  if not InCombatLockdown() then
    local readable, start, dur, enabled = ReadCooldown(id)
    if readable then
      seen[sp] = true
      if enabled == false then
        readyAt[sp] = NEVER
      elseif dur > SHORT and start > 0 then
        readyAt[sp] = start + dur
        if waiting == sp then waiting = nil end -- the game counts it already
      elseif readyAt[sp] ~= NEVER or waiting ~= sp then
        readyAt[sp] = nil
      end
    end
  end
  if not seen[sp] then return false, nil end
  local r = readyAt[sp]
  if r == NEVER then return false, nil end
  local left = r and r - GetTime() or 0
  if left <= 0.05 then return true, 0 end
  return false, left
end

-- a fit spell (Life Tap) is only shown once its mana is known: without it there is no
-- health check either
local function Usable(sp)
  if sp.fit and not amount[sp] then return false end
  return S.Ready(sp)
end

-- the first spell to show now (known, ready), and its ID. Every known spell is checked,
-- so the cooldowns of all of them are read while the player is out of combat.
function S.Candidate()
  local first, firstID
  for _, sp in ipairs(ns.SPELLS) do
    if known[sp] and Usable(sp) and not first then first, firstID = sp, known[sp] end
  end
  return first, firstID
end

-- out of combat, every tick: read every cooldown (also when the slot is hidden, e.g. "only
-- in combat") and the mana of fit spells whose text was not loaded at login
function S.Refresh()
  if InCombatLockdown() then return end
  for sp, id in pairs(known) do
    S.Ready(sp)
    if sp.fit and not amount[sp] then amount[sp] = AmountFromText(id) end
  end
end

-- the known spell that is ready soonest (status line), its ID and seconds left (nil: unknown)
function S.Soonest()
  local best, bestID, bestLeft
  for _, sp in ipairs(ns.SPELLS) do
    if known[sp] then
      local _, left = S.Ready(sp)
      if not best or (left and (not bestLeft or left < bestLeft)) then
        best, bestID, bestLeft = sp, known[sp], left
      end
    end
  end
  return best, bestID, bestLeft
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
  if texture[id] then return texture[id] end
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, t = pcall(C_Spell.GetSpellTexture, id)
    if ok and t and not IsSecret(t) then texture[id] = t return t end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

S.Name = SpellName

local function Cooldown(sp, id)
  local cd = sp.cd or 0
  if GetSpellBaseCooldown then
    local ok, ms = pcall(GetSpellBaseCooldown, id)
    if ok and ms and not IsSecret(ms) and ms > 0 then cd = ms / 1000 end
  end
  return cd
end

-- does this cast use mana at all (also when a proc made it free)? Wand shots and potions do not
local function UsesMana(id)
  local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
  if not getCost then return false end
  local ok, list = pcall(getCost, id)
  if not ok or type(list) ~= "table" then return false end
  for _, c in ipairs(list) do
    if not IsSecret(c.type) and c.type == MANA then return true end
  end
  return false
end

-- the player's own casts start the count in combat (the game's base cooldown, else ours).
-- Inner Focus waits: its cooldown starts with the next spell, which uses up its buff.
local function OnCast(id)
  if id == nil or IsSecret(id) then return end
  local sp = byID[id]
  if waiting and sp ~= waiting and UsesMana(id) then
    local cd = Cooldown(waiting, known[waiting] or waiting.id)
    readyAt[waiting] = cd > GCD and GetTime() + cd or nil
    waiting = nil
  end
  if not sp then return end
  if sp.afterUse then
    readyAt[sp], waiting = NEVER, sp
    return
  end
  local cd = Cooldown(sp, id)
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
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
-- Life Tap gives more with more spirit: its mana is read again after gear changes and fights
local function ReadAmounts()
  if InCombatLockdown() then return end
  for sp, id in pairs(known) do
    if sp.fit then amount[sp] = AmountFromText(id) or amount[sp] end
  end
end
frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if unit == "player" then OnCast(spellID) end
  elseif event == "SPELLS_CHANGED" or (event == "PLAYER_REGEN_ENABLED" and dirty) then
    if ns.db then S.Rebuild() end
  else
    ReadAmounts()
  end
end)
