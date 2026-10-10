-- Minimal World of Warcraft API mock for headless tests (Lua 5.1).
-- Only what Full Mana Forever touches. Every widget keeps its state in plain fields
-- (read them with rawget-free access: methods live in a separate table).
local M = {}

local methods = {}
-- like real frames: unknown fields are nil, only widget methods resolve
local Widget = { __index = methods }
function M.noop() end
for _, name in ipairs({ "ClearFocus", "EnableMouseWheel", "Play", "RegisterForDrag", "SetAutoFocus",
  "SetBlendMode", "SetCheckedTexture", "SetDisabledCheckedTexture", "SetClampedToScreen", "SetColorTexture",
  "SetDuration", "SetFocus", "SetFontObject", "SetFrameLevel", "SetFrameStrata", "SetFromAlpha",
  "SetHighlightFontObject", "SetHighlightTexture", "SetJustifyH", "SetLooping", "SetMaxLetters",
  "SetMovable", "SetNormalFontObject", "SetNormalTexture", "SetNumeric", "SetOwner", "SetPushedTexture",
  "SetRotation", "SetStatusBarColor", "SetStatusBarTexture", "SetTexCoord",
  "SetTextInsets", "SetThumbTexture", "SetToAlpha", "SetToplevel", "SetValueStep", "SetVertexColor",
  "SetWordWrap", "StopMovingOrSizing", "StartMoving", "SetItemByID", "SetJustifyV", "SetMaxLines",
  "SetObeyStepOnDrag", "SetHitRectInsets", "SetDisabledFontObject" }) do
  methods[name] = M.noop
end

M.created = 0
M.all = {}
local function new(kind, parent)
  M.created = M.created + 1
  local o = setmetatable({ kind = kind, shown = true, w = 0, h = 0, points = {}, scripts = {},
    parent = parent, alpha = 1, mouse = false }, Widget)
  M.all[#M.all + 1] = o
  return o
end
M.new = new

function methods:Show()
  local was = self.shown
  self.shown = true
  if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
  local was = self.shown
  self.shown = false
  if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:HookScript(k, f)
  local old = self.scripts[k]
  self.scripts[k] = old and function(...) old(...); f(...) end or f
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetSize(w, h) self.w, self.h = w, h end
function methods:SetWidth(w) self.w = w end
function methods:SetHeight(h) self.h = h end
function methods:GetWidth() return self.w end
function methods:GetHeight() return self.h end
function methods:SetPoint(...) self.points[#self.points + 1] = { ... } end
function methods:SetAllPoints() self.allPoints = true end
function methods:ClearAllPoints() self.points = {} end
function methods:GetPoint() local p = self.points[1] or {} return p[1], p[2], p[3], p[4], p[5] end
function methods:GetLeft() return M.left end
function methods:GetTop() return M.top end
function methods:GetCenter() return M.cx, M.cy end
function methods:SetDesaturated(v) self.desaturated = v and true or false end
function methods:SetScript(k, f) self.scripts[k] = f end
function methods:GetScript(k) return self.scripts[k] end
function methods:CreateTexture() return new("Texture", self) end
function methods:CreateFontString() return new("FontString", self) end
function methods:CreateAnimationGroup() return new("AnimationGroup", self) end
function methods:CreateAnimation() return new("Animation", self) end
function methods:SetText(t) self.text = t end
function methods:GetText() return self.text end
function methods:GetStringWidth() return #(tostring(self.text or "")) * 6 end
function methods:SetTextScale(s) self.textScale = s end
function methods:Raise() self.raised = (self.raised or 0) + 1 end
function methods:SetMotionScriptsWhileDisabled(on) self.motionWhileDisabled = on end
function methods:GetStringHeight() return 12 end
function methods:GetFontString() self.fs = self.fs or new("FontString", self); return self.fs end
function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function methods:SetFont(f, s, fl) self.font = { f, s, fl } end
function methods:GetFrameLevel() return 1 end
function methods:GetChecked() return self.checked end
function methods:SetChecked(v) self.checked = v end
function methods:SetAlpha(a) self.alpha = a end
function methods:SetScale(v) self.scale = v end
function methods:GetScale() return self.scale or 1 end
function methods:SetEnabled(v) self.enabled = v and true or false end
function methods:IsEnabled() return self.enabled ~= false end
function methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function methods:AddLine(t) self.lines = self.lines or {}; self.lines[#self.lines + 1] = t end
function methods:GetAlpha() return self.alpha end
function methods:SetCooldown(st, d) M.calls.SetCooldown = (M.calls.SetCooldown or 0) + 1; self.cdStart, self.cdDur = st, d end
function methods:Clear() self.cdStart, self.cdDur = nil, nil end
function methods:SetHideCountdownNumbers(v) self.hideNumbers = v end
function methods:SetDrawEdge(v) self.drawEdge = v end
function methods:SetDrawBling(v) self.drawBling = v end
function methods:EnableMouse(v) self.mouse = v end
function methods:IsMouseEnabled() return self.mouse end
function methods:SetOrientation(o) self.orient = o end
function methods:GetStatusBarTexture() self.sbt = self.sbt or new("Texture", self); return self.sbt end
function methods:SetGradient(o, a, b)
  assert(type(a) == "table" and type(b) == "table", "SetGradient expects colors")
  self.grad, self.gradMin, self.gradMax = o, a, b
end
function methods:EnableMouseWheel(v) self.wheel = v end
function methods:SetToplevel(v) self.toplevel = v end
function methods:SetValue(v)
  if M.failSetValue and type(v) == "table" then error("secret not accepted") end
  self.value = v
end
function methods:SetMinMaxValues(a, b) M.calls.SetMinMaxValues = (M.calls.SetMinMaxValues or 0) + 1; self.min, self.max = a, b end
function methods:GetVerticalScroll() return self.vscroll or 0 end
function methods:SetVerticalScroll(v) self.vscroll = v end
function methods:SetScrollChild(c) self.child = c end
function methods:GetVerticalScrollRange()
  if not self.child then return 0 end
  return math.max(0, (self.child.h or 0) - (self.h or 0))
end
function methods:SetTexture(t) self.texture = t end
function methods:GetTexture() return self.texture end
function methods:RegisterEvent(e)
  self.events = self.events or {}
  self.events[e] = true
  M.eventFrames[self] = true
end
-- like the real API: the frame only hears these units
function methods:RegisterUnitEvent(e, ...)
  self:RegisterEvent(e)
  self.unitFilter = self.unitFilter or {}
  local units = {}
  for i = 1, select("#", ...) do units[select(i, ...)] = true end
  self.unitFilter[e] = units
end
function methods:UnregisterEvent(e)
  if self.events then self.events[e] = nil end
  if self.unitFilter then self.unitFilter[e] = nil end
end
function methods:UnregisterAllEvents() self.events, self.unitFilter = {}, nil end

M.eventFrames = {}
function M.Fire(e, ...)
  for f in pairs(M.eventFrames) do
    local units = f.unitFilter and f.unitFilter[e]
    if f.events and f.events[e] and f.scripts.OnEvent and (not units or units[(...)]) then
      f.scripts.OnEvent(f, e, ...)
    end
  end
end

-- secret values: a table the addon may pass around but never compare
local secretMT = { __lt = function() error("compare secret") end, __le = function() error("compare secret") end,
  __add = function() error("arith secret") end, __sub = function() error("arith secret") end,
  __concat = function() error("concat secret") end }
function M.secret(v) return setmetatable({ v = v }, secretMT) end
local function isSecret(v) return type(v) == "table" and getmetatable(v) == secretMT end
-- the real engine lets string.format print a secret value; emulate that
local rawformat = string.format
string.format = function(fmt, ...)
  local args = { ... }
  for i = 1, select("#", ...) do if isSecret(args[i]) then args[i] = args[i].v end end
  return rawformat(fmt, unpack(args, 1, select("#", ...)))
end

function M.reset(opts)
  opts = opts or {}
  M.created = 0
  M.all = {}
  M.calls = {}
  M.eventFrames = {}
  M.left, M.top = 500, 600
  M.failSetValue = false
  M.state = {
    manaPct = 1, maxMana = 1000, maxHP = 2000, healthPct = 1,
    bags = opts.bags or {}, cooldowns = {}, class = opts.class or "PRIEST",
    raid = false, group = false, combat = false, instance = "none",
    powerFails = false, locale = opts.locale or "enUS",
    name = opts.name, realm = opts.realm, now = opts.now,
    level = opts.level or 60, minLevel = opts.minLevel or {}, uncached = opts.uncached or {},
  }
  local S = M.state
  local function count(name) M.calls[name] = (M.calls[name] or 0) + 1 end

  _G.CreateFrame = function(kind, name, parent)
    local f = new(kind, parent)
    if name then _G[name] = f end
    return f
  end
  _G.UIParent = new("Frame")
  _G.GameTooltip = new("GameTooltip")
  _G.UISpecialFrames = {}
  _G.CreateColor = function(r, g, b, a)
    return { r = r, g = g, b = b, a = a, GetRGBA = function(s) return s.r, s.g, s.b, s.a end }
  end
  _G.Enum = { LuaCurveType = { Step = 1 } }
  _G.C_CurveUtil = { CreateColorCurve = function()
    count("CreateColorCurve")
    local pts = {}
    return {
      SetType = M.noop,
      AddPoint = function(_, x, c) pts[#pts + 1] = { x, c } end,
      Evaluate = function(_, x)
        local r = pts[1][2]
        for _, p in ipairs(pts) do if x >= p[1] then r = p[2] end end
        return r
      end,
    }
  end }
  -- returns the color the engine would pick; the addon only reads its alpha into SetAlpha
  _G.UnitPowerPercent = function(unit, power, predicted, curve)
    count("UnitPowerPercent")
    if S.powerFails then error("API changed") end
    if curve == M.SCALE100 then return M.secret(S.manaPct * 100) end
    return curve:Evaluate(S.manaPct)
  end
  _G.UnitHealthPercent = function(unit, predicted, curve)
    return curve:Evaluate(S.healthPct)
  end
  _G.UnitPower = function() return M.secret(math.floor(S.maxMana * S.manaPct)) end
  _G.UnitPowerMax = function() return S.maxMana end
  _G.UnitHealthMax = function() return S.maxHP end
  _G.UnitClass = function() return "Class", S.class end
  _G.UnitLevel = function() return S.level end
  _G.UnitName = function(u) if u == "player" then return S.name or "Kesa" end end
  _G.GetRealmName = function() return S.realm or "Forever" end
  _G.time = function() return S.now or 1000000 end
  _G.UnitIsDeadOrGhost = function() return S.dead or false end
  _G.issecretvalue = isSecret
  _G.C_Item = {
    GetItemCount = function(id) count("GetItemCount"); return S.bags[id] or 0 end,
    GetItemIconByID = function(id) return "icon" .. id end,
    GetItemNameByID = function(id) return "Item" .. id end,
    IsEquippedItem = function() return false end,
    GetItemInfoInstant = function(id) return id end,
    -- name, link, quality, itemLevel, minLevel: like the real API, nil until "cached"
    GetItemInfo = function(id)
      if S.uncached[id] then return nil end
      return "Item" .. id, nil, 1, 1, S.minLevel[id] or 0
    end,
    GetItemSpell = function() return "Use" end,
  }
  _G.C_Container = { GetItemCooldown = function(id)
    count("GetItemCooldown")
    local cd = S.cooldowns[id]
    if cd then return cd[1], cd[2], cd[3] == nil and 1 or cd[3] end
    return 0, 0, 1
  end }
  _G.GetTime = function() return S.time or 100 end
  _G.InCombatLockdown = function() return S.combat end
  _G.IsInInstance = function() count("IsInInstance"); return S.instance ~= "none", S.instance end
  _G.IsInRaid = function() count("IsInRaid"); return S.raid end
  _G.IsInGroup = function() return S.group end
  _G.GetLocale = function() return S.locale end
  _G.C_Timer = { NewTicker = function(_, f) M.tick = f; return {} end, After = function(_, f) f() end }
  _G.SlashCmdList = {}
  _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  _G.unpack = unpack or table.unpack
  M.hooks = {}
  _G.hooksecurefunc = function(name, fn) M.hooks[name] = fn end
  _G.CloseSpecialWindows = M.noop
  M.sounds = {}
  _G.PlaySound = function(id) M.sounds[#M.sounds + 1] = id end
  _G.HideUIPanel = function() count("HideUIPanel") end
  _G.SettingsPanel = nil
  _G.Settings = nil
  _G.FullManaForeverDB = nil
  _G.FullManaForeverLog = nil
  _G.FullManaForeverOptions = nil
  _G.FullManaForeverItems = nil
  _G.FullManaForeverAnchor = nil
  _G.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    M.printed[#M.printed + 1] = table.concat(t, " ")
  end
  M.printed = {}
end

-- load the addon files in TOC order into a fresh namespace and log in
M.ROOT = (arg and arg[0] and arg[0]:match("^(.*)tests/")) or "./"
function M.load(saved, opts)
  M.reset(opts)
  local ns = {}
  for line in io.lines(M.ROOT .. "FullManaForever.toc") do
    if line:match("%.lua%s*$") then
      local chunk = assert(loadfile(M.ROOT .. line:gsub("%s+$", "")))
      chunk("FullManaForever", ns)
    end
  end
  _G.FullManaForeverDB = saved
  M.Fire("ADDON_LOADED", "FullManaForever")
  M.Fire("PLAYER_LOGIN")
  return ns
end

-- read a local of a function (for frames the addon keeps private)
function M.upvalue(fn, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
    i = i + 1
  end
end

function M.warnings()
  local out = {}
  for _, p in ipairs(M.printed) do if p:find("ff4444") then out[#out + 1] = p end end
  return out
end

return M
