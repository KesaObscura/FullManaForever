local M, test, eq, ok = T.M, T.test, T.eq, T.ok
local function buttons(ns) return M.upvalue(ns.Layout, "buttons") end
local function click(b) b.scripts.OnClick(b) end

test("profiles: settings of before 0.8.3 become Shared, account things stay outside", function()
  local saved = { dbVersion = 8, iconSize = 60, language = "ruRU", debug = true,
    custom = { { id = 12345, max = 500, group = "potion" } }, disabled = { [3385] = true } }
  local ns = M.load(saved, { class = "PRIEST", level = 20 })
  local shared = saved.profiles.Shared
  eq(shared.iconSize, 60, "size not moved into Shared")
  eq(saved.iconSize, nil, "size left in the account part")
  eq(shared.disabled[3385], true, "switched-off items are per profile")
  eq(saved.language, "ruRU"); eq(saved.debug, true); eq(#saved.custom, 1, "own items moved")
  eq(shared.language, nil, "language copied into the profile")
  eq(ns.db, shared, "character does not use Shared")
  local me = saved.chars["Kesa-Forever"]
  eq(me.profile, "Shared"); eq(me.class, "PRIEST"); eq(me.level, 20); eq(me.seen, 1000000)
end)

test("profiles: an own profile starts as a copy of Shared and is kept when switching back", function()
  local saved = { dbVersion = 8, iconSize = 60 }
  local ns = M.load(saved)
  local P = ns.Profiles
  P.Use("own")
  eq(P.IsOwn(), true)
  eq(ns.db.iconSize, 60, "own profile is no copy of Shared")
  ok(ns.db ~= saved.profiles.Shared, "own profile is Shared itself")
  ns.db.iconSize = 80
  ns.SetItemEnabled(3385, false)
  P.Use("shared")
  eq(ns.db.iconSize, 60, "Shared changed with the own profile")
  ok(ns.IsItemEnabled({ id = 3385 }), "switched-off item leaks into Shared")
  P.Use("own")
  eq(ns.db.iconSize, 80, "own profile lost when switching back")
  ok(not ns.IsItemEnabled({ id = 3385 }), "own switched-off item lost")
  -- after a reload the character is still on its own profile
  ns = M.load(saved)
  eq(ns.db.iconSize, 80, "own profile not used after a reload")
end)

test("profiles: a switch is applied at once (sizes, position, layout)", function()
  local saved = { dbVersion = 8, iconSize = 44 }
  local ns = M.load(saved)
  local b = buttons(ns)[1]
  eq(b.outer.w, 44)
  ns.Profiles.Use("own")
  ns.db.iconSize = 64
  ns.db.point = { "TOPLEFT", "UIParent", "BOTTOMLEFT", 300, 500 }
  ns.Profiles.Use("shared")
  ns.Profiles.Use("own")
  eq(b.outer.w, 64, "icons keep the old size after a switch")
  local anchor = _G.FullManaForeverAnchor
  eq(anchor.points[1][4], 300, "frame not moved to the profile's position")
  eq(anchor.points[1][5], 500)
end)

test("profiles: another character copies, the copy can be undone; reset and delete", function()
  local saved = { dbVersion = 8, iconSize = 60 }
  local ns = M.load(saved, { class = "MAGE", level = 30 })
  ns.Profiles.Use("own")
  ns.db.iconSize = 80
  -- an alt logs in: it starts on Shared and sees Kesa
  ns = M.load(saved, { name = "Alt", class = "DRUID", level = 12, now = 1000000 + 3 * 86400 })
  local P = ns.Profiles
  eq(P.IsOwn(), false, "a new character does not start on Shared")
  eq(ns.db.iconSize, 60)
  local others = P.Others()
  eq(#others, 1); eq(others[1].name, "Kesa"); eq(others[1].class, "MAGE"); eq(others[1].level, 30)
  ok(P.CopyFrom("Kesa-Forever"))
  eq(P.IsOwn(), true); eq(ns.db.iconSize, 80, "not copied")
  ns.db.iconSize = 90
  eq(saved.profiles["Kesa-Forever"].iconSize, 80, "the copy is shared with the original")
  ok(P.Undo())
  eq(P.IsOwn(), false, "undo did not go back to Shared"); eq(ns.db.iconSize, 60)
  eq(saved.profiles["Alt-Forever"], nil, "undo kept the copied profile")
  eq(P.Undo(), false, "a second undo")
  -- reset of the own profile leaves Shared alone
  P.Use("own"); ns.db.iconSize = 70
  P.Reset()
  eq(ns.db.iconSize, 44, "reset did not bring the default back")
  eq(saved.profiles.Shared.iconSize, 60, "reset changed Shared")
  P.Undo()
  eq(ns.db.iconSize, 70, "reset not undone")
  -- delete Kesa's profile: Kesa disappears from the list, undo brings it back
  ok(P.Delete("Kesa-Forever"))
  eq(#P.Others(), 0)
  eq(P.Delete("Alt-Forever"), false, "own profile in use deleted")
  P.Undo()
  eq(#P.Others(), 1, "delete not undone")
end)

test("profiles: /fmf profile switches, copies by name and undoes", function()
  local saved = { dbVersion = 8 }
  local ns = M.load(saved)
  SlashCmdList.FULLMANAFOREVER("profile own")
  ns.db.iconSize = 80
  ns = M.load(saved, { name = "Alt" })
  M.printed = {}
  SlashCmdList.FULLMANAFOREVER("profile")
  local out = table.concat(M.printed, "\n")
  ok(out:find(ns.L.profShared, 1, true) and out:find("Kesa", 1, true), "status line: " .. out)
  SlashCmdList.FULLMANAFOREVER("profile copy KESA")
  eq(ns.db.iconSize, 80, "copy by name")
  M.printed = {}
  SlashCmdList.FULLMANAFOREVER("profile copy nobody")
  ok(table.concat(M.printed):find("nobody", 1, true), "unknown name not reported")
  SlashCmdList.FULLMANAFOREVER("profile undo")
  eq(ns.Profiles.IsOwn(), false)
  SlashCmdList.FULLMANAFOREVER("profile own")
  eq(ns.Profiles.IsOwn(), true)
  SlashCmdList.FULLMANAFOREVER("profile shared")
  eq(ns.Profiles.IsOwn(), false)
end)

test("profiles: the settings window switches the profile and shows its values", function()
  local saved = { dbVersion = 8, iconSize = 60 }
  local ns = M.load(saved)
  ns.Profiles.Use("own")
  ns.db.iconSize = 80
  ns.Profiles.Use("shared")
  ns.ToggleOptions(true)
  local function find()
    local prof, size
    for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
      if w.entries and w.entries[1].value == "shared" then prof = w end
      if w.minus and w.label and w.label.text == ns.L.optSize .. ":" then size = w end
    end
    return prof, size
  end
  local prof, size = find()
  eq(prof.text, ns.L.profShared); eq(size.value.text, "60")
  prof.Select("own")
  ok(_G.FullManaForeverOptions:IsShown(), "window closed by the switch")
  prof, size = find()
  eq(prof.text, ns.L.profOwn); eq(size.value.text, "80", "window shows the old profile")
end)

test("profiles window: lists other characters, copy and delete ask first, undo", function()
  local saved = { dbVersion = 8 }
  local ns = M.load(saved, { class = "MAGE", level = 30 })
  ns.Profiles.Use("own"); ns.db.iconSize = 80
  ns = M.load(saved, { name = "Alt", now = 1000000 + 2 * 86400 })
  _G.RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc7eb" } }
  ns.ToggleProfiles(true)
  local pwin = _G.FullManaForeverProfiles
  -- find the row of Kesa by its text
  local row
  for _, f in ipairs(M.all) do
    if f.kind == "FontString" and type(f.text) == "string" and f.text:find("Kesa", 1, true) then row = f.parent end
  end
  ok(row, "Kesa not listed")
  ok(row.name.text:find("ff3fc7eb", 1, true), "no class colour: " .. row.name.text)
  ok(row.info.text:find("30", 1, true) and row.info.text:find(ns.L.seenDays:format(2), 1, true), "info: " .. row.info.text)
  click(row.copy)
  ok(pwin.confirm.shown, "copy without asking")
  eq(ns.Profiles.IsOwn(), false, "copied before the answer")
  click(pwin.no)
  eq(ns.Profiles.IsOwn(), false)
  click(row.copy); click(pwin.yes)
  eq(ns.Profiles.IsOwn(), true); eq(ns.db.iconSize, 80)
  -- now Shared can be copied too (first row, no delete), Kesa is the second
  local rowsList = M.upvalue(M.upvalue(ns.ToggleProfiles, "RefreshProfiles"), "rows")
  ok(rowsList[1].name.text:find(ns.L.profShared, 1, true) and not rowsList[1].del.shown, "no Shared row first")
  local kesa = rowsList[2]
  ok(kesa.name.text:find("Kesa", 1, true), "Kesa not second")
  click(kesa.del); click(pwin.yes)
  eq(#ns.Profiles.Others(), 0, "not deleted")
  ok(not kesa.shown, "deleted character still listed")
end)

test("profiles window: every button has a tooltip", function()
  local saved = { dbVersion = 8 }
  local ns = M.load(saved)
  ns.Profiles.Use("own")
  ns = M.load(saved, { name = "Alt" })
  ns.ToggleProfiles(true)
  local pwin = _G.FullManaForeverProfiles
  local n = 0
  for _, f in ipairs(M.all) do
    if f.kind == "Button" then
      local p, inWin = f.parent, false
      while p do if p == pwin then inWin = true end p = p.parent end
      if inWin then
        n = n + 1
        -- "Yes" gets the tooltip of the question it answers when it is asked
        if f ~= pwin.yes then ok(f.scripts.OnEnter, "no tooltip on " .. tostring(f.text)) end
      end
    end
  end
  ok(n >= 6, "buttons found: " .. n)
end)

test("windows: opening a window again brings it to the front; a copy keeps the profiles window on top", function()
  local saved = { dbVersion = 8 }
  local ns = M.load(saved)
  ns.Profiles.Use("own")
  ns = M.load(saved, { name = "Alt" })
  ns.ToggleOptions(true)
  ns.ToggleProfiles(true)
  ns.ToggleLibrary(true)
  local pwin, lib = _G.FullManaForeverProfiles, _G.FullManaForeverItems
  local p0, l0 = pwin.raised or 0, lib.raised or 0
  ns.ToggleProfiles(true); ns.ToggleLibrary(true)
  ok((pwin.raised or 0) > p0, "profiles window not raised when opened again")
  ok((lib.raised or 0) > l0, "item list not raised when opened again")
  local rows = M.upvalue(M.upvalue(ns.ToggleProfiles, "RefreshProfiles"), "rows")
  local p1 = pwin.raised
  rows[1].copy.scripts.OnClick(rows[1].copy); pwin.yes.scripts.OnClick(pwin.yes)
  eq(ns.Profiles.IsOwn(), true)
  ok(pwin.raised > p1, "profiles window left behind the rebuilt settings window")
end)

test("Esc closes the settings and the profiles window", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  ns.ToggleProfiles(true)
  ok(M.hooks.CloseSpecialWindows, "no Esc hook")
  M.hooks.CloseSpecialWindows()
  ok(not _G.FullManaForeverOptions:IsShown(), "settings window stays open on Esc")
  ok(not _G.FullManaForeverProfiles:IsShown(), "profiles window stays open on Esc")
end)

test("popups: over the settings, settings dimmed; Esc closes one window per press", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  local win = FullManaForeverOptions
  ok(not win.shade.shown, "dimmed without a popup")
  ns.ToggleProfiles(true)
  local pwin = FullManaForeverProfiles
  ok(win.shade.shown, "settings not dimmed under the profiles window")
  eq(pwin.points[1][2], win, "profiles window not centred on the settings")
  -- Esc as the game does it: every listed window is hidden, then the hook runs
  local function Esc()
    for _, name in ipairs(UISpecialFrames) do
      local f = _G[name]
      if f and f:IsShown() then f:Hide() end
    end
    M.hooks.CloseSpecialWindows()
  end
  Esc()
  ok(not pwin:IsShown(), "profiles window still open")
  ok(win:IsShown(), "first Esc closed the settings too")
  ok(not win.shade.shown, "settings still dimmed")
  M.state.time = 101 -- the next key press comes later
  Esc()
  ok(not win:IsShown(), "second Esc did not close the settings")
  -- the item list on its own: a normal window, nothing dimmed
  ns.ToggleLibrary(true)
  ok(FullManaForeverItems:IsShown())
  ok(not win.shade.shown)
end)
