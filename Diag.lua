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

local function HeaderText()
  local _, class = UnitClass("player")
  local okL, lvl = Call(UnitLevel, "player")
  local okM, max = Call(UnitPowerMax, "player", MANA)
  return ("v%s %s level=%s maxMana=%s combat=%s API: GetPowerRegen=%s C_Spell.GetSpellPowerCost=%s C_UnitAuras=%s"):format(
    ns.VERSION, Show(class), okL and Show(lvl) or "?", okM and Show(max) or "?",
    tostring(InCombatLockdown()), tostring(GetPowerRegen ~= nil),
    tostring(C_Spell ~= nil and C_Spell.GetSpellPowerCost ~= nil), tostring(C_UnitAuras ~= nil))
    .. (" ScaleTo100=%s percent=%s"):format(tostring(CurveConstants ~= nil and CurveConstants.ScaleTo100 ~= nil),
      ns.ManaPercent and (ns.ManaPercent() ~= nil and "ok" or "nil") or "?")
end

------------------------------------------------------------------------
-- collector: one event frame, two outputs (chat probe, saved log)
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
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
  if probe.running and chatToo ~= false then ToChat(Stamp() .. " " .. text) end
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
      .. "  combat=" .. tostring(InCombatLockdown()) .. "  " .. RegenText() .. WatchText())
  end
end

local function OnUpdate()
  local now = GetTime()
  if now < clock.next then return end
  clock.next = now + 2
  local regen = RegenText()
  -- chat: every 2 s; log: on change, or every 10 s with the mana event count
  if probe.running and now - clock.start > 1 then
    ToChat(("%.0f s combat=%s mana events=%d %s"):format(now - clock.start, tostring(InCombatLockdown()),
      clock.power, regen))
  end
  if regen ~= clock.lastRegen or now - clock.lastSample >= 10 then
    ToLog(("sample combat=%s mana events=%d %s%s%s fsr=%.1f%s"):format(tostring(InCombatLockdown()),
      clock.power, regen, WatchText(), DisplayText(), ns.FsrLeft and ns.FsrLeft() or 0, RecentCosts()))
    clock.lastRegen, clock.lastSample = regen, now
  end
  clock.power = 0
  if probe.running and now - probe.start >= 30 then
    probe.running = false
    ToChat("5sr probe done. Please copy the chat lines above.")
  end
  if not Active() then
    frame:UnregisterAllEvents()
    frame:SetScript("OnUpdate", nil)
  end
end

local function Start()
  if frame:GetScript("OnUpdate") then return end
  clock.start, clock.next, clock.power, clock.lastRegen, clock.lastAura, clock.lastSample =
    GetTime(), 0, 0, nil, nil, GetTime()
  for _, e in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
  -- a diagnostic must never break the game UI: any surprise (a secret where we expect a
  -- plain value) is swallowed
  frame:SetScript("OnEvent", function(...) pcall(OnEvent, ...) end)
  frame:SetScript("OnUpdate", function(...) pcall(OnUpdate, ...) end)
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
  log.lines[#log.lines + 1] = ("---- session %s ----"):format(date and date("%Y-%m-%d %H:%M") or "?")
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
            add(("spell [%s] %s %s%s cost=%s cd=%s : %s"):format(OneLine(line.name), Show(it.spellID),
              OneLine(it.name), it.isPassive and " (passive)" or "", CostOf(it.spellID),
              CooldownText(it.spellID), Describe(it.spellID)))
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
            passive and " (passive)" or "", CostOf(id), CooldownText(id), Describe(id)))
        end
      end
    end
  end
  return n
end

local function ScanTalents(add)
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return 0 end
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

function ns.Scan()
  if not log then ns.Print("log not ready yet") return end
  if InCombatLockdown() then ns.Print("scan: not in combat, please") return end
  local lines = log.lines
  local function add(text)
    if #lines < MAX_LINES then lines[#lines + 1] = "scan " .. text end
  end
  lines[#lines + 1] = ("---- scan %s ----"):format(date and date("%Y-%m-%d %H:%M") or "?")
  add(HeaderText())
  local counts = {}
  for _, part in ipairs({ { "spells", ScanSpells }, { "talents", ScanTalents }, { "items", ScanItems } }) do
    local ok, n = pcall(part[2], add)
    counts[#counts + 1] = part[1] .. "=" .. (ok and tostring(n) or ("error " .. tostring(n):sub(1, 80)))
    if not ok then add(part[1] .. " error: " .. tostring(n):sub(1, 200)) end
  end
  ns.Print(("scan done: %s. /reload, then send WTF\\Account\\<account>\\SavedVariables\\FullManaForever.lua")
    :format(table.concat(counts, " ")))
end

function ns.LogCommand(arg)
  if not log then ns.Print("log not ready yet") return end
  if arg == "on" then
    if not log.on then log.on = true; BeginSession() end
    ns.Print("log ON. Play 10-20 minutes with fights, then /fmf log off and /reload."
      .. " File: WTF\\Account\\<account>\\SavedVariables\\FullManaForever.lua")
  elseif arg == "off" then
    if log.on then ToLog("log off"); log.on = false end
    ns.Print(("log OFF, %d lines. /reload (or log out) so the game writes the file."):format(#log.lines))
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
