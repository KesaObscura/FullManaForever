local M, test, eq, ok = T.M, T.test, T.eq, T.ok

local function loadStrings()
  M.reset()
  local ns = {}
  assert(loadfile(M.ROOT .. "Locale.lua"))("FullManaForever", ns)
  local strings = M.upvalue(ns.SetLanguage, "strings") or M.upvalue(M.upvalue(ns.SetLanguage, "Resolve"), "strings")
  return ns, strings
end

local function placeholders(str)
  local out = {}
  for p in str:gmatch("%%[%d%.]*[sdf%%]") do out[#out + 1] = p end
  return table.concat(out, " ")
end

test("every language has exactly the English keys and placeholders", function()
  local _, strings = loadStrings()
  local en = strings.enUS
  for lang, t in pairs(strings) do
    if lang ~= "esMX" then
      for k, v in pairs(en) do
        ok(rawget(t, k), lang .. " misses " .. k)
        eq(placeholders(rawget(t, k)), placeholders(v), lang .. "." .. k .. " placeholders")
      end
      for k in pairs(t) do ok(en[k], lang .. " has extra key " .. k) end
    end
  end
end)

test("every key used in the code exists, and every key is used", function()
  local _, strings = loadStrings()
  local en = strings.enUS
  local code = ""
  for _, f in ipairs({ "Core.lua", "Options.lua", "Library.lua", "Regen.lua", "Diag.lua" }) do
    local h = assert(io.open(M.ROOT .. f)); code = code .. h:read("*a"); h:close()
  end
  for k in code:gmatch("L%.([%a_][%w_]*)") do ok(en[k], "missing key " .. k) end
  -- keys built at runtime
  local dynamic = { grp_ = true, col_ = true, strat = true, show = true, tipGrp_ = true }
  for k in pairs(en) do
    local used = code:find("L%." .. k .. "[^%w_]") or code:find('"' .. k .. '"')
    if not used then
      for prefix in pairs(dynamic) do if k:sub(1, #prefix) == prefix then used = true end end
    end
    ok(used, "unused key " .. k)
  end
end)
