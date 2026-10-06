-- Full Mana Forever - diagnostics for the five-second-rule / regen feature (0.7.0).
-- Collects what the game hands an addon when the player casts and while mana comes back,
-- and whether each value is secret. Two outputs:
--   /fmf probe 5sr    30 seconds, printed to chat
--   /fmf log on|off   long recording into FullManaForeverLog (SavedVariables); the game
--                     writes it to WTF\Account\<account>\SavedVariables\FullManaForever.lua
--                     on /reload or logout.
-- Secret values are never stored or printed, only marked as SECRET: a secret string in
-- SavedVariables or in a chat line could break both. Texts stay English (bug reports).

local _, ns = ...
local MANA = 0
local MAX_LINES = 6000

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

local function Show(v)
  if v == nil then return "nil" end
  if IsSecret(v) then return "SECRET" end
  if type(v) == "number" then
    if v == math.floor(v) then return tostring(v) end
    return ("%.2f"):format(v)
  end
  return tostring(v)
end

local function Call(fn, ...)
  if not fn then return false end
  return pcall(fn, ...)
end

------------------------------------------------------------------------
-- facts
------------------------------------------------------------------------
local function RegenText()
  if not GetPowerRegen then return "regen=missing" end
  local ok, base, casting = pcall(GetPowerRegen)
  if not ok then return "regen=error" end
  local text = ("regen/s base=%s casting=%s"):format(Show(base), Show(casting))
  if GetManaRegen then -- older API, maybe readable where GetPowerRegen is secret
    local ok2, b2, c2 = pcall(GetManaRegen)
    text = text .. (ok2 and (" manaRegen=%s/%s"):format(Show(b2), Show(c2)) or " manaRegen=error")
  end
  return text
end

-- can a secret regen value be shown as text (like the mana numbers on our bar)?
local testText
local function DisplayText()
  if not GetPowerRegen then return "" end
  local ok, base = pcall(GetPowerRegen)
  if not ok or not IsSecret(base) then return "" end
  testText = testText or UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  testText:Hide()
  local okF, str = pcall(string.format, "%.1f/s", base)
  if not okF then return " text=format-error" end
  local okS = pcall(testText.SetText, testText, str)
  return okS and " text=ok" or " text=settext-error"
end

-- buffs that change regen, asked one by one (the full list was empty in combat)
local WATCH = { { 15271, "SpiritTap" }, { 29166, "Innervate" }, { 14751, "InnerFocus" } }
local function WatchText()
  local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
  if not get then return " byID=missing" end
  local out = {}
  for _, w in ipairs(WATCH) do
    local ok, a = pcall(get, w[1])
    local state = not ok and "error" or a == nil and "no" or IsSecret(a) and "SECRET"
      or (IsSecret(a.spellId) and "secret-fields" or "yes")
    out[#out + 1] = w[2] .. "=" .. state
  end
  return " byID " .. table.concat(out, " ")
end

local function AuraText()
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return "buffs: API missing" end
  local names, secret, why = {}, 0, ""
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok then why = " (error)" break end
    if IsSecret(a) then why = " (secret)" break end
    if not a then break end
    if IsSecret(a.name) or IsSecret(a.spellId) then
      secret = secret + 1
    else
      names[#names + 1] = ("%s(%s)"):format(tostring(a.name), tostring(a.spellId))
    end
  end
  return ("buffs: %s%s%s"):format(#names > 0 and table.concat(names, ", ") or "-",
    secret > 0 and (" +" .. secret .. " secret") or "", why)
end

local function SpellText(id)
  local name = "?"
  if C_Spell and C_Spell.GetSpellName and not IsSecret(id) then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok then name = Show(n) end
  end
  local costs, getCost = {}, (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
  local ok, list = false, nil
  if getCost and not IsSecret(id) then ok, list = pcall(getCost, id) end
  if ok and type(list) == "table" then
    for _, c in ipairs(list) do
      costs[#costs + 1] = ("type=%s cost=%s"):format(Show(c.type), Show(c.cost))
    end
  end
  local cost = not getCost and "API missing" or not ok and "error"
    or (#costs > 0 and table.concat(costs, "; ") or "none")
  return ("spell=%s %s cost: %s"):format(Show(id), name, cost)
end

-- cooldown of a spell as the game reports it (readable or SECRET, in and out of combat)
local function CooldownText(id)
  if id == nil or IsSecret(id) then return "?" end
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    if not ok then return "error" end
    if IsSecret(cd) then return "SECRET" end
    if type(cd) == "table" then return ("%s+%s"):format(Show(cd.startTime), Show(cd.duration)) end
    return Show(cd)
  end
  if GetSpellCooldown then
    local ok, start, dur = pcall(GetSpellCooldown, id)
    if ok then return ("%s+%s"):format(Show(start), Show(dur)) end
    return "error"
  end
  return "API missing"
end

-- current mana cost of a spell (procs like Clearcasting or Inner Focus may show up as 0)
local function CostOf(id)
  local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
  if not getCost then return "?" end
  local ok, list = pcall(getCost, id)
  if not ok or type(list) ~= "table" then return "?" end
  for _, c in ipairs(list) do
    if IsSecret(c.type) or c.type == MANA then return Show(c.cost) end
  end
  return "0"
end

local recent = {} -- the last mana spells cast: their cost is sampled again later
local function NoteManaSpell(id)
  if id == nil or IsSecret(id) then return end
  for i = #recent, 1, -1 do if recent[i] == id then table.remove(recent, i) end end
  table.insert(recent, 1, id)
  recent[5] = nil
end

local function RecentCosts()
  if #recent == 0 then return "" end
  local out = {}
  for _, id in ipairs(recent) do out[#out + 1] = id .. "=" .. CostOf(id) end
  return " costs " .. table.concat(out, ",")
end

-- max health: is it readable in combat? (the rune's HP check needs it)
local function HealthText()
  local ok, max = Call(UnitHealthMax, "player")
  return " maxHP=" .. (ok and Show(max) or "?")
end

-- mana potions in the bags: the game's cooldown (start+duration, enable) and what the
-- addon makes of it. Shows whether a potion drunk in combat can come back in the same fight.
local function PotionText()
  if not (ns.GROUPS and ns.FullList and C_Container and C_Container.GetItemCooldown) then return "" end
  local gi
  for i, g in ipairs(ns.GROUPS) do if g.key == "potion" then gi = i end end
  if not gi then return "" end
  local out = {}
  for _, it in ipairs(ns.FullList(gi)) do
    local okN, n = Call(C_Item.GetItemCount, it.id)
    if okN and (IsSecret(n) or (n and n > 0)) then
      local ok, s, d, en = Call(C_Container.GetItemCooldown, it.id)
      local okR, ready = Call(ns.CooldownState, it.id)
      out[#out + 1] = ("%d x%s cd=%s+%s en=%s ready=%s"):format(it.id, Show(n),
        ok and Show(s) or "?", ok and Show(d) or "?", ok and Show(en) or "?",
        okR and tostring(ready) or "?")
    end
  end
  if #out == 0 then return " pots none" end
  return " pots " .. table.concat(out, ", ")
end

local function HeaderText()
  local _, class = UnitClass("player")
  local race = UnitRace and select(2, UnitRace("player"))
  local okL, lvl = Call(UnitLevel, "player")
  local okM, max = Call(UnitPowerMax, "player", MANA)
  return ("v%s %s %s level=%s maxMana=%s combat=%s API: GetPowerRegen=%s C_Spell.GetSpellPowerCost=%s C_UnitAuras=%s"):format(
    ns.VERSION, Show(class), Show(race), okL and Show(lvl) or "?", okM and Show(max) or "?",
    tostring(InCombatLockdown()), tostring(GetPowerRegen ~= nil),
    tostring(C_Spell ~= nil and C_Spell.GetSpellPowerCost ~= nil), tostring(C_UnitAuras ~= nil))
    .. HealthText() .. (" ScaleTo100=%s percent=%s"):format(tostring(CurveConstants ~= nil and CurveConstants.ScaleTo100 ~= nil),
      ns.ManaPercent and (ns.ManaPercent() ~= nil and "ok" or "nil") or "?")
end

------------------------------------------------------------------------
-- collector: one event frame, two outputs (chat probe, saved log)
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
-- group casts need every unit (party1-4, raidN); it listens only while the log runs
local groupFrame = CreateFrame("Frame")
groupFrame.allUnits = true
local probe = { running = false }
local log -- FullManaForeverLog once the saved variables are loaded
local clock = { start = 0, next = 0, power = 0, lastRegen = nil, lastAura = nil, lastSample = 0 }

local function Stamp()
  return ("%.1f"):format(GetTime() - clock.start)
end

local function ToChat(text) ns.Print(text) end

local function ToLog(text)
  if not (log and log.on) then return end
  local n = #log.lines
  if n >= MAX_LINES then
    log.on = false
    log.lines[n + 1] = "log full: stopped"
    ns.Print("log full (" .. MAX_LINES .. " lines): stopped. /reload, then send the file.")
    return
  end
  log.lines[n + 1] = Stamp() .. " " .. text
end

local function Emit(text, chatToo)
  ToLog(text)
  -- chat lines count from the start of the probe, even when the log was already running
  if probe.running and chatToo ~= false then
    ToChat(("%.1f %s"):format(GetTime() - probe.start, text))
  end
end

local EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_POWER_UPDATE",
  "UNIT_AURA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_MAXPOWER" }

local function Active() return probe.running or (log and log.on) end

local function OnEvent(_, event, unit, arg2, arg3)
  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    Emit((event == "PLAYER_REGEN_DISABLED" and "combat start  " or "combat end  ") .. RegenText())
  elseif unit ~= "player" then
    return
  elseif event == "UNIT_POWER_UPDATE" then
    if arg2 == "MANA" then clock.power = clock.power + 1 end
  elseif event == "UNIT_MAXPOWER" then
    if arg2 == "MANA" then
      local ok, max = Call(UnitPowerMax, "player", MANA)
      Emit("maxMana=" .. (ok and Show(max) or "?"))
    end
  elseif event == "UNIT_AURA" then
    local text = AuraText()
    if text ~= clock.lastAura then clock.lastAura = text; Emit(text) end
  else
    local text = SpellText(arg3)
    if text:find("type=0", 1, true) then NoteManaSpell(arg3) end
    Emit((event == "UNIT_SPELLCAST_SUCCEEDED" and "cast " or "channel ") .. text
      .. "  cd=" .. CooldownText(arg3)
      .. "  combat=" .. tostring(InCombatLockdown()) .. "  " .. RegenText() .. WatchText()
      .. HealthText() .. PotionText())
  end
end

local function Sample(now)
  local regen = RegenText()
  -- chat: every 2 s; log: on change, or every 10 s with the mana event count
  if probe.running and now - probe.start > 1 then
    ToChat(("%.0f s combat=%s mana events=%d %s"):format(now - probe.start, tostring(InCombatLockdown()),
      clock.power, regen))
  end
  if regen ~= clock.lastRegen or now - clock.lastSample >= 10 then
    ToLog(("sample combat=%s mana events=%d %s%s%s fsr=%.1f%s%s%s"):format(tostring(InCombatLockdown()),
      clock.power, regen, WatchText(), DisplayText(), ns.FsrLeft and ns.FsrLeft() or 0, RecentCosts(),
      HealthText(), PotionText()))
    clock.lastRegen, clock.lastSample = regen, now
  end
end

-- the sampling is guarded on its own: a surprise there must not keep the probe running
local function OnUpdate()
  local now = GetTime()
  if now < clock.next then return end
  clock.next = now + 2
  pcall(Sample, now)
  clock.power = 0
  if probe.running and now - probe.start >= 30 then
    probe.running = false
    ToChat("5sr probe done. Please copy the chat lines above.")
  end
  if not Active() then
    groupFrame:UnregisterAllEvents()
    frame:UnregisterAllEvents()
    frame:SetScript("OnUpdate", nil)
  end
end

-- group members' casts: is the spell ID readable (also in combat)? Innervate and Mana Tide
-- always, other casts only the first 40 per session (enough to answer, small log)
local GROUP_WATCH = { [29166] = "Innervate", [16190] = "ManaTide", [17354] = "ManaTide", [17359] = "ManaTide" }
local groupCount = 0

local function OnGroupEvent(_, event, a1, a2, a3, a4)
  if event == "CHAT_MSG_ADDON" then
    if a1 == "FMF" then
      ToLog(("addon msg text=%s channel=%s sender=%s combat=%s"):format(Show(a2), Show(a3), Show(a4),
        tostring(InCombatLockdown())))
    end
    return
  end
  local unit, id = a1, a3
  if IsSecret(unit) or type(unit) ~= "string" or not (unit:match("^party%d$") or unit:match("^raid%d+$")) then
    return
  end
  local watch = not IsSecret(id) and GROUP_WATCH[id]
  if not watch and groupCount >= 40 then return end
  groupCount = groupCount + 1
  local _, class = UnitClass(unit)
  local name = "?"
  if not IsSecret(id) and C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok then name = Show(n) end
  end
  ToLog(("group cast %s %s spell=%s %s%s combat=%s"):format(unit, Show(class), Show(id), name,
    watch and (" WATCH " .. watch) or "", tostring(InCombatLockdown())))
end

local function Start()
  if frame:GetScript("OnUpdate") then return end
  groupCount = 0
  pcall(groupFrame.RegisterEvent, groupFrame, "UNIT_SPELLCAST_SUCCEEDED")
  pcall(groupFrame.RegisterEvent, groupFrame, "CHAT_MSG_ADDON")
  groupFrame:SetScript("OnEvent", function(...) pcall(OnGroupEvent, ...) end)
  clock.start, clock.next, clock.power, clock.lastRegen, clock.lastAura, clock.lastSample =
    GetTime(), 0, 0, nil, nil, GetTime()
  for _, e in ipairs(EVENTS) do
    if e:find("^UNIT_") and frame.RegisterUnitEvent then
      pcall(frame.RegisterUnitEvent, frame, e, "player")
    else
      pcall(frame.RegisterEvent, frame, e)
    end
  end
  -- a diagnostic must never break the game UI: any surprise (a secret where we expect a
  -- plain value) is swallowed
  frame:SetScript("OnEvent", function(...) pcall(OnEvent, ...) end)
  frame:SetScript("OnUpdate", OnUpdate)
end

function ns.Probe5SR()
  if probe.running then ns.Print("5sr probe already running") return end
  probe.running, probe.start = true, GetTime()
  Start()
  ToChat("5sr probe: 30 s. Cast a few spells (in and out of combat), use a potion, wait for full mana.")
  ToChat(HeaderText())
  ToChat(AuraText())
end

local function BeginSession()
  Start()
  if #log.lines < MAX_LINES then
    log.lines[#log.lines + 1] = ("---- session %s ----"):format(date and date("%Y-%m-%d %H:%M") or "?")
  end
  ToLog(HeaderText())
  ToLog(AuraText())
end

------------------------------------------------------------------------
-- /fmf scan: every spell in the spell book, talents and every item with a "Use:" effect,
-- with the game's own descriptions (Forever numbers, not guides) -> into the saved log
------------------------------------------------------------------------
local function OneLine(text)
  if text == nil then return "" end
  if IsSecret(text) then return "SECRET" end
  return (tostring(text):gsub("[\r\n]+", " | "))
end

local function Describe(id)
  local get = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
  if not get or id == nil then return "" end
  local ok, d = pcall(get, id)
  return ok and OneLine(d) or "error"
end

-- the spell's own cooldown in the game data (seconds), also for spells not learned yet
local function BaseCd(id)
  if not GetSpellBaseCooldown or id == nil or IsSecret(id) then return "?" end
  local ok, ms = pcall(GetSpellBaseCooldown, id)
  if not ok or ms == nil then return "?" end
  if IsSecret(ms) then return "SECRET" end
  return Show(ms / 1000)
end

local scanTip
local function TooltipLines(setter, ...)
  if not scanTip then
    local ok, tip = pcall(CreateFrame, "GameTooltip", "FullManaForeverScanTip", nil, "GameTooltipTemplate")
    if not ok or not tip then return "" end
    scanTip = tip
  end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if not pcall(scanTip[setter], scanTip, ...) then return "" end
  local out = {}
  for i = 1, scanTip:NumLines() do
    local fs = _G["FullManaForeverScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t and not IsSecret(t) and t ~= "" then out[#out + 1] = t end
  end
  scanTip:Hide()
  return OneLine(table.concat(out, " | "))
end

local function ScanSpells(add)
  local n = 0
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
      if line then
        for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
          local it = C_SpellBook.GetSpellBookItemInfo(j, bank)
          if it and it.spellID then
            n = n + 1
            -- the book may also list spells for later levels ("future"): those count too
            local future = Enum and Enum.SpellBookItemType and it.itemType == Enum.SpellBookItemType.FutureSpell
            add(("spell [%s] %s %s%s%s cost=%s cd=%s : %s"):format(OneLine(line.name), Show(it.spellID),
              OneLine(it.name), it.isPassive and " (passive)" or "", future and " (not learned yet)" or "",
              CostOf(it.spellID),
              CooldownText(it.spellID) .. " base=" .. BaseCd(it.spellID), Describe(it.spellID)))
          end
        end
      end
    end
  elseif GetNumSpellTabs then
    for i = 1, GetNumSpellTabs() do
      local tab, _, offset, num = GetSpellTabInfo(i)
      for j = offset + 1, offset + num do
        local name = GetSpellBookItemName(j, BOOKTYPE_SPELL or "spell")
        local _, id = GetSpellBookItemInfo(j, BOOKTYPE_SPELL or "spell")
        if id then
          n = n + 1
          local passive = IsPassiveSpell and IsPassiveSpell(j, BOOKTYPE_SPELL or "spell")
          add(("spell [%s] %s %s%s cost=%s cd=%s : %s"):format(OneLine(tab), Show(id), OneLine(name),
            passive and " (passive)" or "", CostOf(id), CooldownText(id) .. " base=" .. BaseCd(id), Describe(id)))
        end
      end
    end
  end
  return n
end

-- talents through the newer trait API (C_ClassTalents + C_Traits)
local function ScanTraits(add)
  local cid = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
  if not cid then add("talents: no active talent config") return 0 end
  local info = C_Traits.GetConfigInfo(cid)
  local n = 0
  for _, tree in ipairs(info and info.treeIDs or {}) do
    for _, node in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
      local ni = C_Traits.GetNodeInfo(cid, node)
      for _, entry in ipairs(ni and ni.entryIDs or {}) do
        local ei = C_Traits.GetEntryInfo(cid, entry)
        local di = ei and ei.definitionID and C_Traits.GetDefinitionInfo(ei.definitionID)
        local id = di and (di.spellID or di.overriddenSpellID)
        if id then
          n = n + 1
          local okN, name = pcall(C_Spell.GetSpellName, id)
          add(("talent tree=%s node=%s %s %s %s/%s : %s"):format(Show(tree), Show(node), Show(id),
            okN and OneLine(name) or "?", Show(ni.currentRank), Show(ni.maxRanks), Describe(id)))
        end
      end
    end
  end
  return n
end

local function ScanTalents(add)
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then
    if C_ClassTalents and C_Traits then return ScanTraits(add) end
    add(("talents: old API missing. GetNumTalentTabs=%s GetTalentInfo=%s C_ClassTalents=%s C_Traits=%s"
      .. " C_SpecializationInfo=%s C_Talent=%s GetTalentTabInfo=%s"):format(tostring(GetNumTalentTabs ~= nil),
      tostring(GetTalentInfo ~= nil), tostring(C_ClassTalents ~= nil), tostring(C_Traits ~= nil),
      tostring(C_SpecializationInfo ~= nil), tostring(_G.C_Talent ~= nil), tostring(GetTalentTabInfo ~= nil)))
    return 0
  end
  local n = 0
  for tab = 1, GetNumTalentTabs() do
    for i = 1, GetNumTalents(tab) do
      local name, _, tier, column, rank, maxRank = GetTalentInfo(tab, i)
      if name then
        n = n + 1
        add(("talent %d/%d %s %s/%s (row %s) : %s"):format(tab, i, OneLine(name), Show(rank), Show(maxRank),
          Show(tier), TooltipLines("SetTalent", tab, i)))
      end
    end
  end
  return n
end

-- spells that give or save mana, learned above level 1 (a new character cannot see them in
-- its spell book). IDs from Classic; the scan prints the name Forever has for each ID, so a
-- wrong or changed ID shows up as a different name. Talents and racials come from the
-- talent and spell book scans.
local KNOWN = {
  29166, -- Innervate (druid)
  12051, -- Evocation (mage)
  6117, 1463, 1459, 23028, -- Mage Armor, Mana Shield, Arcane Intellect, Arcane Brilliance
  759, 3552, 10053, 10054, -- Conjure Mana Agate, Jade, Citrine, Ruby
  1454, 18220, -- Life Tap, Dark Pact (warlock)
  5675, 16190, -- Mana Spring Totem, Mana Tide Totem (shaman)
  19742, 25894, 20166, -- Blessing / Greater Blessing of Wisdom, Seal of Wisdom (paladin)
  14751, 15270, -- Inner Focus, Spirit Tap (priest)
}

local function ScanKnown(add)
  if not (C_Spell and C_Spell.GetSpellName) then return 0 end
  local n = 0
  for _, id in ipairs(KNOWN) do
    if C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    local d = Describe(id)
    if not ok or name == nil then
      add(("known %d ? (not loaded, /fmf scan again)"):format(id))
    else
      n = n + 1
      add(("known %d %s cost=%s cd=%s : %s"):format(id, OneLine(name), CostOf(id),
        CooldownText(id) .. " base=" .. BaseCd(id),
        d ~= "" and d or "(no description yet, /fmf scan again)"))
    end
  end
  return n
end

-- every spell a class trainer teaches in Forever, as the addon TrainerSpells lists it (its
-- table is read at run time on the player's own client; nothing of it ships with this addon)
local TRAINER_CLASSES = { "PRIEST", "MAGE", "DRUID", "SHAMAN", "PALADIN", "WARLOCK", "HUNTER" }

local function SortedKeys(t)
  local keys = {}
  for k in pairs(t) do if type(k) == "number" then keys[#keys + 1] = k end end
  table.sort(keys)
  return keys
end

local function TrainerList(fn)
  local data = _G.TrainerSpellsBuiltin
  if type(data) ~= "table" then return false end
  for _, class in ipairs(TRAINER_CLASSES) do
    local levels = data[class]
    if type(levels) == "table" then
      for _, lvl in ipairs(SortedKeys(levels)) do
        for _, id in ipairs(SortedKeys(levels[lvl])) do fn(class, lvl, id, levels[lvl][id]) end
      end
    end
  end
  return true
end

local function ScanTrainer(add)
  local n = 0
  local ok = TrainerList(function(class, lvl, id, info)
    n = n + 1
    local race = type(info) == "table" and info.race or nil
    if type(race) == "table" then race = table.concat(race, "/") end
    local okN, name = pcall(C_Spell and C_Spell.GetSpellName, id)
    add(("trainer %s L%d %d %s%s%s cost=%s base=%s : %s"):format(class, lvl, id,
      okN and name ~= nil and OneLine(name) or "?",
      type(info) == "table" and info.rank and (" r" .. tostring(info.rank)) or "",
      race and (" race=" .. tostring(race)) or "", CostOf(id), BaseCd(id), Describe(id)))
  end)
  if not ok then add("trainer: TrainerSpells is not loaded") end
  return n
end

local function ItemLine(where, id, add)
  if not id then return 0 end
  local spellName, spellID = C_Item.GetItemSpell(id)
  if not spellID then return 0 end
  local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  add(("item %s %s %s use=%s %s : %s"):format(where, Show(id), OneLine(name), Show(spellID), OneLine(spellName),
    Describe(spellID)))
  return 1
end

local function ScanItems(add)
  local n, seen = 0, {}
  for slot = 1, 19 do
    local id = GetInventoryItemID and GetInventoryItemID("player", slot)
    if id and not seen[id] then seen[id] = true; n = n + ItemLine("slot" .. slot, id, add) end
  end
  if C_Container and C_Container.GetContainerNumSlots then
    for bag = 0, 4 do
      for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
        local id = C_Container.GetContainerItemID(bag, slot)
        if id and not seen[id] then seen[id] = true; n = n + ItemLine("bag", id, add) end
      end
    end
  end
  return n
end

local function RunScan(parts)
  local lines = log.lines
  local dropped = 0
  local function add(text)
    if #lines < MAX_LINES then lines[#lines + 1] = "scan " .. text else dropped = dropped + 1 end
  end
  if #lines < MAX_LINES then
    lines[#lines + 1] = ("---- scan %s ----"):format(date and date("%Y-%m-%d %H:%M") or "?")
  end
  add(HeaderText())
  local counts = {}
  for _, part in ipairs(parts) do
    local ok, n = pcall(part[2], add)
    counts[#counts + 1] = part[1] .. "=" .. (ok and tostring(n) or ("error " .. tostring(n):sub(1, 80)))
    if not ok then add(part[1] .. " error: " .. tostring(n):sub(1, 200)) end
  end
  if dropped > 0 then
    ns.Print(("log full: %d scan lines dropped. /fmf log clear, then /fmf scan again."):format(dropped))
  end
  ns.Print(("scan done: %s. /reload, then send WTF\\Account\\<account>\\SavedVariables\\FullManaForever.lua")
    :format(table.concat(counts, " ")))
end

-- /fmf scan: own spells, talents, items, known mana spells. /fmf scan trainer: all trainer
-- spells of the mana classes; the game loads their texts first, the list is written 3 s later.
function ns.Scan(what)
  if not log then ns.Print("log not ready yet") return end
  if InCombatLockdown() then ns.Print("scan: not in combat, please") return end
  if what == "trainer" then
    if not TrainerList(function(_, _, id)
      if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
    end) then
      ns.Print("scan trainer: the addon TrainerSpells is not loaded")
      return
    end
    ns.Print("scan trainer: loading spell texts, 3 s ...")
    local function write() RunScan({ { "trainer", ScanTrainer } }) end
    if C_Timer and C_Timer.After then C_Timer.After(3, write) else write() end
    return
  end
  RunScan({ { "spells", ScanSpells }, { "talents", ScanTalents }, { "items", ScanItems }, { "known", ScanKnown } })
end

function ns.LogCommand(arg)
  if not log then ns.Print("log not ready yet") return end
  if arg == "on" then
    if #log.lines >= MAX_LINES then
      ns.Print(("log full (%d lines). /fmf log clear first."):format(#log.lines))
      return
    end
    if not log.on then log.on = true; BeginSession() end
    ns.Print("log ON. Play 10-20 minutes with fights, then /fmf log off and /reload."
      .. " File: WTF\\Account\\<account>\\SavedVariables\\FullManaForever.lua")
  elseif arg == "off" then
    if log.on then ToLog("log off"); log.on = false end
    ns.Print(("log OFF, %d lines. /reload (or log out) so the game writes the file."):format(#log.lines))
  elseif arg == "chat" then
    -- may an addon send chat and addon messages (in combat too)? Whispers itself only.
    local me = UnitName("player")
    local okW, errW = pcall(SendChatMessage, "Full Mana Forever: chat test", "WHISPER", nil, me)
    local okP = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
      and pcall(C_ChatInfo.RegisterAddonMessagePrefix, "FMF")
    local okA, resA = false, "API missing"
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
      okA, resA = pcall(C_ChatInfo.SendAddonMessage, "FMF", "test", "WHISPER", me)
    end
    local text = ("chat test combat=%s whisper=%s prefix=%s addon=%s %s"):format(tostring(InCombatLockdown()),
      okW and "sent" or ("error " .. tostring(errW):sub(1, 80)), tostring(okP),
      okA and "sent" or "error", Show(resA))
    ToLog(text)
    ns.Print(text .. (log.on and "" or "  (/fmf log on first, to record the answer)"))
  elseif arg == "clear" then
    wipe(log.lines)
    ns.Print("log cleared")
  else
    ns.Print(("log is %s, %d lines. /fmf log on | off | clear"):format(log.on and "ON" or "OFF", #log.lines))
  end
end

-- the log keeps running across /reload and logins until it is switched off
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  FullManaForeverLog = type(FullManaForeverLog) == "table" and FullManaForeverLog or {}
  log = FullManaForeverLog
  log.lines = log.lines or {}
  if log.on then
    BeginSession()
    ns.Print(("log is ON (%d lines). /fmf log off when you are done."):format(#log.lines))
  end
end)
