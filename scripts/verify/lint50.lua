-- lint50.lua: Lua 5.0 / vanilla-client lint for what luac50 -p can't catch. Runs under lua50.
-- usage: lua50 lint50.lua <file.lua>...            prints "file:line: rule: message", exit 1 on any finding
--        lua50 lint50.lua --toc <addon.toc>        lints every .lua listed in the .toc
--        lua50 lint50.lua --selftest <fixture>...  each fixture's first line: "-- expect: <rule>[,<rule>]" or "-- expect: none"
--                                                  ("compile-error" = rejected by the 5.0 parser, same as luac50 -p)

local UNAVAILABLE = { "issecurevalue", "issecurevariable", "scrubsecurecall", "securecallfunction", "secureexecuterange", "pcallwithenv" }
local CONDITION_WORDS = { "if", "elseif", "while", "until", "and", "or", "not" }

local function ReadFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- Returns the end index of a 5.0 long bracket starting at i ("[["), nested "[[" counted; nil if unterminated.
local function LongBracketEnd(s, i)
  local depth = 0
  local n = string.len(s)
  while i <= n do
    local two = string.sub(s, i, i + 1)
    if two == "[[" then
      depth = depth + 1
      i = i + 2
    elseif two == "]]" then
      depth = depth - 1
      i = i + 2
      if depth == 0 then return i - 1 end
    else
      i = i + 1
    end
  end
  return nil
end

-- Blanks comments, long strings and quoted strings (newlines kept, so line numbers stay intact).
local function StripSource(s)
  local out = {}
  local n = string.len(s)
  local i = 1
  local function Blank(from, to)
    local chunk = string.sub(s, from, to)
    table.insert(out, (string.gsub(chunk, "[^\n]", " ")))
  end
  while i <= n do
    local c = string.sub(s, i, i)
    local two = string.sub(s, i, i + 1)
    if two == "--" then
      local j
      if string.sub(s, i + 2, i + 3) == "[[" then
        j = LongBracketEnd(s, i + 2) or n
      else
        j = string.find(s, "\n", i, true)
        j = j and (j - 1) or n
      end
      Blank(i, j)
      i = j + 1
    elseif two == "[[" then
      local j = LongBracketEnd(s, i) or n
      Blank(i, j)
      i = j + 1
    elseif c == "\"" or c == "'" then
      local j = i + 1
      while j <= n do
        local d = string.sub(s, j, j)
        if d == "\\" then
          j = j + 2
        elseif d == c or d == "\n" then
          break
        else
          j = j + 1
        end
      end
      if j > n then j = n end
      Blank(i, j)
      i = j + 1
    else
      table.insert(out, c)
      i = i + 1
    end
  end
  return table.concat(out)
end

local function IsIdentChar(ch)
  return ch ~= "" and string.find(ch, "[%w_]") ~= nil
end

-- Returns true if word occurs in line as a whole identifier.
local function HasWord(line, word)
  local init = 1
  while true do
    local a, b = string.find(line, word, init, true)
    if not a then return false end
    if not IsIdentChar(string.sub(line, a - 1, a - 1)) and not IsIdentChar(string.sub(line, b + 1, b + 1)) then
      return true
    end
    init = b + 1
  end
end

local function FindHex(line)
  local init = 1
  while true do
    local a, b = string.find(line, "0[xX]%x+", init)
    if not a then return nil end
    local prev = string.sub(line, a - 1, a - 1)
    if not IsIdentChar(prev) then return string.sub(line, a, b) end
    init = b + 1
  end
end

local function LintLine(line, report)
  local hex = FindHex(line)
  if hex then report("hex", "hex numeral " .. hex .. " (Lua 5.0 has none; use tonumber(\"" .. hex .. "\", 16))") end
  if HasWord(line, "gmatch") then report("gmatch", "string.gmatch is 5.1-only; use string.gfind") end
  for _, name in ipairs(UNAVAILABLE) do
    if HasWord(line, name) then report("unavailable-api", name .. " is unavailable on this client") end
  end
  if string.find(line, "InCombatLockdown%s*%(") then
    for _, w in ipairs(CONDITION_WORDS) do
      if HasWord(line, w) then
        report("incombat-condition", "InCombatLockdown() always returns false here; use PLAYER_REGEN_DISABLED/ENABLED")
        break
      end
    end
  end
end

-- Lints one file; returns list of {line, rule, msg}, or nil + error.
local function LintFile(path)
  local src = ReadFile(path)
  if not src then return nil, "cannot read " .. path end
  local stripped = StripSource(src)
  local findings = {}
  local lineNo = 0
  for line in string.gfind(stripped .. "\n", "([^\n]*)\n") do
    lineNo = lineNo + 1
    LintLine(line, function(rule, msg) table.insert(findings, { line = lineNo, rule = rule, msg = msg }) end)
  end
  return findings
end

local function TocFiles(tocPath)
  local root = string.gsub(tocPath, "[/\\][^/\\]*$", "")
  if root == tocPath then root = "." end
  local files = {}
  for line in io.lines(tocPath) do
    line = string.gsub(line, "\r", "")
    if string.find(line, "%.lua$") and not string.find(line, "^#") then
      table.insert(files, root .. "/" .. string.gsub(line, "\\", "/"))
    end
  end
  return files
end

local function RunLint(files)
  local total = 0
  local errors = 0
  for _, path in ipairs(files) do
    local findings, err = LintFile(path)
    if not findings then
      print(err)
      errors = errors + 1
    else
      for _, f in ipairs(findings) do
        print(path .. ":" .. f.line .. ": " .. f.rule .. ": " .. f.msg)
        total = total + 1
      end
    end
  end
  print("lint50: " .. total .. " findings")
  if total > 0 or errors > 0 then os.exit(1) end
end

local function RunSelftest(files)
  local failed = 0
  for _, path in ipairs(files) do
    local src = ReadFile(path) or ""
    local _, _, expectList = string.find(src, "^%-%- expect: ([%w%-,]+)")
    local expected = {}
    if expectList and expectList ~= "none" then
      for rule in string.gfind(expectList, "[^,]+") do expected[rule] = true end
    end
    local got = {}
    if not loadfile(path) then got["compile-error"] = true end
    for _, f in ipairs(LintFile(path) or {}) do got[f.rule] = true end
    local ok = expectList ~= nil
    for rule in pairs(expected) do if not got[rule] then ok = false end end
    for rule in pairs(got) do if not expected[rule] then ok = false end end
    local gotList = {}
    for rule in pairs(got) do table.insert(gotList, rule) end
    table.sort(gotList)
    print((ok and "PASS " or "FAIL ") .. path .. "  expect=" .. tostring(expectList) .. " got=" .. (table.getn(gotList) > 0 and table.concat(gotList, ",") or "none"))
    if not ok then failed = failed + 1 end
  end
  print("lint50 selftest: " .. failed .. " failed")
  if failed > 0 then os.exit(1) end
end

local mode = arg[1]
if mode == "--selftest" then
  local files = {}
  for i = 2, table.getn(arg) do table.insert(files, arg[i]) end
  RunSelftest(files)
elseif mode == "--toc" then
  RunLint(TocFiles(arg[2]))
elseif mode then
  local files = {}
  for i = 1, table.getn(arg) do table.insert(files, arg[i]) end
  RunLint(files)
else
  print("usage: lua50 lint50.lua [--toc <file.toc> | --selftest <fixture>... | <file.lua>...]")
  os.exit(2)
end
