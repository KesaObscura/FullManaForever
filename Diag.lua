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

-- group members' casts: is the spell ID readable (also in combat), and who cast it? Spells
-- that give mana are logged every time (Classic IDs; a rank with another ID in Forever still
-- shows up once below), every other spell once per class, so the log names everything the
-- group casts without filling up
local GROUP_WATCH = {
  [29166] = "Innervate", [16190] = "ManaTide", [17354] = "ManaTide", [17359] = "ManaTide",
  [5675] = "ManaSpring", [10495] = "ManaSpring", [10496] = "ManaSpring", [10497] = "ManaSpring",
  [19742] = "Wisdom", [19850] = "Wisdom", [19852] = "Wisdom", [19853] = "Wisdom", [19854] = "Wisdom",
  [25290] = "Wisdom", [25894] = "GreaterWisdom", [25918] = "GreaterWisdom",
  [20166] = "SealWisdom", [20356] = "SealWisdom", [20357] = "SealWisdom", [20271] = "Judgement",
  [1459] = "Intellect", [1460] = "Intellect", [1461] = "Intellect", [10156] = "Intellect",
  [10157] = "Intellect", [23028] = "Brilliance",
  [14752] = "DivineSpirit", [14818] = "DivineSpirit", [14819] = "DivineSpirit", [27841] = "DivineSpirit",
  [27681] = "PrayerSpirit",
  [2800] = "LayOnHands", [10310] = "LayOnHands", -- ranks 2 (30) and 3 (50): 250 / 550 mana to the target
  [5504] = "Water", [5505] = "Water", [5506] = "Water", [6127] = "Water", [10138] = "Water",
  [10139] = "Water", [10140] = "Water",
}
local MAX_GROUP_LINES = 300
local groupCount, groupSeen = 0, {}
local rosterDumps, rosterSize = 0, nil

local function Who(unit)
  if not UnitName then return "?" end
  local ok, name = pcall(UnitName, unit)
  return ok and Show(name) or "error"
end

-- who is in the group (class, level, is the name readable): at log start and when the size
-- changes, at most 5 times per session
local function LogRoster()
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  if IsSecret(n) or n == rosterSize or rosterDumps >= 5 then return end
  rosterSize, rosterDumps = n, rosterDumps + 1
  local raid = IsInRaid and IsInRaid() or false
  ToLog(("group roster members=%s raid=%s combat=%s"):format(Show(n), tostring(raid), tostring(InCombatLockdown())))
  local count = raid and n or math.max(n - 1, 0)
  for i = 1, math.min(count, 40) do
    local unit = (raid and "raid" or "party") .. i
    local _, class = UnitClass(unit)
    ToLog(("group member %s %s level=%s who=%s"):format(unit, Show(class), Show(UnitLevel(unit)),
      Who(unit)))
  end
end

local function OnGroupEvent(_, event, a1, a2, a3, a4)
  if event == "GROUP_ROSTER_UPDATE" then LogRoster() return end
  if event == "CHAT_MSG_ADDON" then
    if a1 == "FMF" then
      ToLog(("addon msg text=%s channel=%s sender=%s combat=%s"):format(Show(a2), Show(a3), Show(a4),
        tostring(InCombatLockdown())))
    end
    return
  end
  local unit, id = a1, a3
  if groupCount >= MAX_GROUP_LINES then return end
  if IsSecret(unit) then
    -- a secret unit cannot be told apart from target or nameplates: logged a few times
    if not groupSeen.secretUnit or groupSeen.secretUnit < 5 then
      groupSeen.secretUnit = (groupSeen.secretUnit or 0) + 1
      groupCount = groupCount + 1
      ToLog("group cast unit=SECRET spell=" .. Show(id))
    end
    return
  end
  if type(unit) ~= "string" or not (unit:match("^party%d$") or unit:match("^raid%d+$")) then
    return
  end
  local _, class = UnitClass(unit)
  local watch = not IsSecret(id) and GROUP_WATCH[id]
  if not watch then
    local key = Show(class) .. ":" .. Show(id)
    local limit = IsSecret(id) and 20 or 1 -- a secret ID: a few samples, it may be anything
    if (groupSeen[key] or 0) >= limit then return end
    groupSeen[key] = (groupSeen[key] or 0) + 1
  end
  groupCount = groupCount + 1
  local name = "?"
  if not IsSecret(id) and C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok then name = Show(n) end
  end
  ToLog(("group cast %s %s spell=%s %s%s combat=%s who=%s"):format(unit, Show(class), Show(id), name,
    watch and (" WATCH " .. watch) or "", tostring(InCombatLockdown()), Who(unit)))
end

local function Start()
  if frame:GetScript("OnUpdate") then return end
  groupCount, groupSeen, rosterDumps, rosterSize = 0, {}, 0, nil
  pcall(groupFrame.RegisterEvent, groupFrame, "UNIT_SPELLCAST_SUCCEEDED")
  pcall(groupFrame.RegisterEvent, groupFrame, "CHAT_MSG_ADDON")
  pcall(groupFrame.RegisterEvent, groupFrame, "GROUP_ROSTER_UPDATE")
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
  pcall(LogRoster)
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
    -- the group gets an invisible addon message: does it reach other FMF users (in combat too)?
    local channel = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY") or nil
    local okG, resG = false, "no group"
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then
      okG, resG = pcall(C_ChatInfo.SendAddonMessage, "FMF", "test " .. Show(me), channel)
    end
    local text = ("chat test combat=%s whisper=%s prefix=%s addon=%s %s group=%s %s %s"):format(
      tostring(InCombatLockdown()), okW and "sent" or ("error " .. tostring(errW):sub(1, 80)), tostring(okP),
      okA and "sent" or "error", Show(resA), Show(channel), okG and "sent" or "error", Show(resG))
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
