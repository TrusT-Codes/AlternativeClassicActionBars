-- usage: lua load.lua <repoRoot>  -> prints inventory (ACAB keys + addon _G writes) to stdout
local root = arg[1]
local files = {}
for line in io.lines(root .. "/AlternativeClassicActionBars.toc") do
  line = string.gsub(line, "\r", "")
  if string.find(line, "%.lua$") and not string.find(line, "^#") then table.insert(files, line) end
end
local stub
stub = setmetatable({}, {__index=function() return function() return stub end end, __call=function() return stub end,
  __concat=function() return "" end, __lt=function() return false end, __le=function() return false end,
  __add=function() return 0 end, __sub=function() return 0 end, __mul=function() return 0 end, __div=function() return 0 end, __unm=function() return 0 end})
local written = {}
local real = {}
setmetatable(_G, {__index=function(t,k) return stub end, __newindex=function(t,k,v) written[k]=true; rawset(t,k,v) end})
for _, f in ipairs(files) do
  local fn, err = loadfile(root .. "/" .. f)
  if not fn then print("LOADERR " .. err) os.exit(1) end
  local ok, e = pcall(fn)
  if not ok then print("RUNERR " .. f .. ": " .. tostring(e)) os.exit(1) end
end
local out = {}
local A = rawget(_G, "AlternativeClassicActionBars")
for k in pairs(A or {}) do table.insert(out, "ACAB." .. tostring(k)) end
for k in pairs(written) do table.insert(out, "_G." .. tostring(k)) end
table.sort(out)
for _, l in ipairs(out) do print(l) end
