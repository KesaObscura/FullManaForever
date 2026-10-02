local M, test, eq, ok = T.M, T.test, T.eq, T.ok

local function libReg(ns) return M.upvalue(ns.RebuildLibrary, "BuildContent") and M.upvalue(M.upvalue(ns.RebuildLibrary, "BuildContent"), "rowReg") end

test("item list: rebuilding does not pile up widgets or frames", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  ns.RebuildLibrary()
  local frames = M.created
  for _ = 1, 10 do ns.RebuildLibrary() end
  eq(M.created, frames, "frames created by 10 rebuilds:")
end)

test("item list follows /fmf item and /fmf item clear", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  SlashCmdList.FULLMANAFOREVER("item 4242 300 potion")
  local rows = M.upvalue(ns.RebuildLibrary, "rows") or M.upvalue(M.upvalue(ns.RebuildLibrary, "BuildContent"), "rows")
  local found = false
  for _, r in ipairs(rows) do if r.it and r.it.id == 4242 and r.frame.shown then found = true end end
  ok(found, "added item not listed")
  SlashCmdList.FULLMANAFOREVER("item clear")
  for _, r in ipairs(rows) do ok(not (r.it and r.it.id == 4242 and r.frame.shown), "cleared item still listed") end
end)

test("item list scrollbar takes the mouse", function()
  local ns = M.load(nil)
  ns.ToggleLibrary(true)
  local sbar = M.upvalue(ns.ToggleLibrary, "sbar") or M.upvalue(M.upvalue(ns.ToggleLibrary, "Build"), "sbar")
  ok(sbar and sbar.mouse, "slider has no mouse")
end)

test("options: choosing the current layout or language does not rebuild the window", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  local win = FullManaForeverOptions
  local frames = M.created
  -- find the dropdowns by their list rows and pick the already active values
  local picked = 0
  for _, w in ipairs(M.upvalue(ns.RefreshOptions, "widgets")) do
    if w.Select and w.entries then
      if w.entries[1].value == false then w.Select(ns.db.vertical); picked = picked + 1 end
      if w.entries[1].value == "auto" then w.Select(ns.db.language); picked = picked + 1 end
    end
  end
  eq(picked, 2, "dropdowns found")
  eq(FullManaForeverOptions, win, "window rebuilt")
  eq(M.created, frames, "frames created")
end)

test("options: a failing widget build leaves the registry usable", function()
  local ns = M.load(nil)
  local ui = ns.UI
  ok(ui.WithRegistry, "no WithRegistry helper")
  local mine = {}
  local okRun = pcall(ui.WithRegistry, mine, function() error("boom") end)
  ok(not okRun, "error swallowed")
  ns.ToggleOptions(true)
  eq(#mine, 0, "options widgets went into the item list registry")
end)

test("options: settings button does not touch Blizzard panels in combat", function()
  local ns = M.load(nil)
  M.state.combat = true
  _G.SettingsPanel = M.new("Frame")
  _G.Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = M.noop }
  ns.InitOptions()
  local btn = M.upvalue(ns.InitOptions, "panelButton")
  btn.scripts.OnClick(btn)
  eq(M.calls.HideUIPanel, nil, "HideUIPanel called in combat")
end)

test("options window stays on top of the item list when clicked", function()
  local ns = M.load(nil)
  ns.ToggleOptions(true)
  ok(FullManaForeverOptions.toplevel, "not toplevel")
end)
