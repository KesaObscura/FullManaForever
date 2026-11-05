-- Full Mana Forever - profiles.
-- The saved variables stay account-wide (copying between characters needs that). Inside
-- them: "Shared", used by every character that has nothing else, and an own profile per
-- character, keyed by "Name-Realm". An own profile starts as a copy of Shared and is kept
-- when the character switches back to Shared. Profiles are keyed by name, so named
-- profiles could come later. Language, own items and the debug switches are account-wide.

local _, ns = ...
local P = {}
ns.Profiles = P

local SHARED = "Shared"
P.SHARED = SHARED

-- keys of the saved variables that are not part of a profile
P.ACCOUNT = {
  dbVersion = true, seenVersion = true, language = true, custom = true, debug = true,
  scale100 = true, profiles = true, chars = true, optPoint = true,
}

local root  -- FullManaForeverDB
local me    -- this character's key, nil while the game does not tell the name
local undo  -- one step back per session: the profile (and character) the last change touched

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

local function DeepCopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = DeepCopy(v) end
  return c
end
P.DeepCopy = DeepCopy

-- "Name Surname-Realm". Forever characters have a surname: UnitName("player") returns it
-- second (where other clients return the realm), so two characters may share a first name.
-- Also returns the name as shown, the realm, and the key used before 0.8.6 (first name only).
local function CharKey()
  if not UnitName then return nil end
  local ok, name, surname = pcall(UnitName, "player")
  if not ok or type(name) ~= "string" or IsSecret(name) or name == "" then return nil end
  if UNKNOWNOBJECT and name == UNKNOWNOBJECT then return nil end
  local realm = GetRealmName and GetRealmName()
  if type(realm) ~= "string" or IsSecret(realm) or realm == "" then realm = "?" end
  realm = realm:gsub("%s", "")
  local full = name
  if type(surname) == "string" and not IsSecret(surname) and surname ~= "" then
    full = name .. " " .. surname
  end
  return full .. "-" .. realm, full, realm, name .. "-" .. realm
end

-- 0.8.3: the settings so far become the shared profile, every character starts on it
function P.Migrate(r)
  r.profiles = type(r.profiles) == "table" and r.profiles or {}
  r.chars = type(r.chars) == "table" and r.chars or {}
  -- a damaged file (edited by hand): entries that are not tables are dropped (0.9.2)
  for k, v in pairs(r.profiles) do if type(v) ~= "table" then r.profiles[k] = nil end end
  for k, v in pairs(r.chars) do if type(v) ~= "table" then r.chars[k] = nil end end
  if not r.profiles[SHARED] then
    local shared = {}
    for k, v in pairs(r) do
      if not P.ACCOUNT[k] then shared[k] = v end
    end
    for k in pairs(shared) do r[k] = nil end
    r.profiles[SHARED] = shared
  end
end

-- the character is known: remember it (class, level, last login) for the profiles window
function P.Init(r)
  root = r
  P.Migrate(r)
  local full, realm, oldKey
  me, full, realm, oldKey = CharKey()
  if me then
    -- 0.8.6: keys get the surname; the character's record and own profile move along
    -- only when the class matches: before 0.8.6 two characters with the same first name
    -- shared one key, the other one must not take its profile (0.9.2)
    local okC0, _, myClass = pcall(UnitClass, "player")
    local old = r.chars[oldKey]
    local sameClass = old and (not old.class or not okC0 or type(myClass) ~= "string"
      or IsSecret(myClass) or old.class == myClass)
    if oldKey ~= me and not r.chars[me] and old and sameClass then
      r.chars[me], r.chars[oldKey] = r.chars[oldKey], nil
      if r.profiles[oldKey] then r.profiles[me], r.profiles[oldKey] = r.profiles[oldKey], nil end
      if r.chars[me].profile == oldKey then r.chars[me].profile = me end
    end
    local c = r.chars[me] or { profile = SHARED }
    c.name, c.realm = full, realm
    r.chars[me] = c
    local okC, _, class = pcall(UnitClass, "player")
    if okC and type(class) == "string" and not IsSecret(class) then c.class = class end
    local okL, lvl = pcall(UnitLevel, "player")
    if okL and type(lvl) == "number" and not IsSecret(lvl) and lvl > 0 then c.level = lvl end
    if time then c.seen = time() end
  end
end

function P.Me() return me end
local function Split(key) -- "Name Surname-Realm" -> name, realm (the realm has no "-")
  local name, realm = key:match("^(.*)%-([^%-]*)$")
  return name or key, realm
end

function P.MyName()
  local c = me and root.chars[me]
  return c and c.name or (me and (Split(me)))
end

function P.MyRealm()
  local c = me and root.chars[me]
  return c and c.realm or (me and select(2, Split(me)))
end

-- name of the profile this character uses (a missing one falls back to Shared)
function P.ActiveName()
  local c = me and root.chars[me]
  local name = c and c.profile or SHARED
  if not root.profiles[name] then name = SHARED end
  return name
end

function P.IsOwn() return me ~= nil and P.ActiveName() == me end

function P.ActiveTable()
  local name = P.ActiveName()
  if not root.profiles[name] then root.profiles[name] = {} end
  return root.profiles[name]
end

function P.Level(lvl)
  local c = me and root.chars[me]
  if c and type(lvl) == "number" and not IsSecret(lvl) then c.level = lvl end
end

-- only what the change touches is kept, so undo does not take back later changes
-- (settings changed after a delete, other characters' logins)
local function Snapshot(key, charKey)
  undo = { key = key, profile = DeepCopy(root.profiles[key]), charKey = charKey,
    char = charKey and DeepCopy(root.chars[charKey]) }
end

local function Changed()
  if ns.ApplyProfile then ns.ApplyProfile() end
end

-- "shared" or "own". Own is created as a copy of Shared the first time.
function P.Use(which)
  if not me then return false end
  local c = root.chars[me]
  if which == "own" then
    if not root.profiles[me] then root.profiles[me] = DeepCopy(root.profiles[SHARED]) end
    c.profile = me
  else
    c.profile = SHARED
  end
  Changed()
  return true
end

-- this character gets its own profile as a copy of another one (a character key or Shared)
function P.CopyFrom(name)
  if not me or not root.profiles[name] or name == me then return false end
  Snapshot(me, me)
  root.profiles[me] = DeepCopy(root.profiles[name])
  root.chars[me].profile = me
  Changed()
  return true
end

-- the profile in use back to the defaults (language and own items are not in it)
function P.Reset()
  Snapshot(P.ActiveName())
  root.profiles[P.ActiveName()] = {}
  Changed()
  return true
end

-- the own profile of another character; that character uses Shared at its next login
function P.Delete(key)
  if key == me or key == SHARED or not root.profiles[key] then return false end
  Snapshot(key, key)
  root.profiles[key] = nil
  root.chars[key] = nil
  return true
end

function P.CanUndo() return undo ~= nil end

function P.Undo()
  if not undo then return false end
  root.profiles[undo.key] = undo.profile
  local ck = undo.charKey
  if ck == me and root.chars[me] and undo.char then
    root.chars[me].profile = undo.char.profile -- level and last login stay current
  elseif ck then
    root.chars[ck] = undo.char
  end
  undo = nil
  Changed()
  return true
end

-- other characters with their own profile, last seen first:
-- { key, name, realm, class, level, seen }
function P.Others()
  local list = {}
  for key, c in pairs(root.chars) do
    if key ~= me and root.profiles[key] then
      local name, realm = Split(key)
      list[#list + 1] = { key = key, name = c.name or name, realm = c.realm or realm, class = c.class,
        level = c.level, seen = c.seen or 0 }
    end
  end
  table.sort(list, function(a, b)
    if a.seen ~= b.seen then return a.seen > b.seen end
    return a.key < b.key
  end)
  return list
end

-- a character with its own profile by name: "Anna Stone", "Anna Stone-Realm" or only "Anna" when
-- no other character has that first name; case does not matter (Latin letters)
function P.Find(text)
  text = text and text:lower()
  if not text or text == "" then return nil end
  for _, o in ipairs(P.Others()) do
    if o.key:lower() == text then return o end
  end
  for _, o in ipairs(P.Others()) do
    if o.name:lower() == text then return o end
  end
  local found
  for _, o in ipairs(P.Others()) do
    if (o.name:match("^(%S+)") or ""):lower() == text then
      if found then return nil end -- two characters with this first name: say the surname too
      found = o
    end
  end
  return found
end
