-- Spike H0.3 — merge ditto's extras into a lazyvim.json (prototype of what
-- internal/config would do in Go).
--
--   nvim --clean -l merge-extras.lua <in.json> <out.json> <extra>...
--
-- Rule: union. The repo's extras keep their position, ditto's are appended in
-- the given order, duplicates are dropped (first occurrence wins). Every other
-- key (version, install_version, news, unknown ones) is kept as is. The order
-- in the file does not matter to LazyVim: lazyvim.plugins.xtras deduplicates
-- and sorts by priority and then by name.
local inp, out = arg[1], arg[2]
assert(inp and out, "usage: merge-extras.lua <in.json> <out.json> <extra>...")

local data = { extras = {} }
local f = io.open(inp, "r")
if f then
  local text = f:read("*a")
  f:close()
  data = vim.json.decode(text, { luanil = { object = true, array = true } }) or {}
  data.extras = data.extras or {}
end

local seen, merged = {}, {}
local function add(e)
  if type(e) == "string" and e ~= "" and not seen[e] then
    seen[e] = true
    merged[#merged + 1] = e
  end
end
for _, e in ipairs(data.extras) do
  add(e)
end
for i = 3, #arg do
  add(arg[i])
end
data.extras = merged

-- Same layout as LazyVim's own writer (sorted keys, 2-space indent), so a
-- later save by LazyVim produces no diff.
local function encode(v, indent)
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  elseif t == "number" or t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local nxt = indent .. "  "
    local parts = {}
    if vim.islist(v) and (#v > 0 or v == data.extras) then
      for _, x in ipairs(v) do
        parts[#parts + 1] = nxt .. encode(x, nxt)
      end
      if #parts == 0 then
        return "[]"
      end
      return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    local keys = vim.tbl_keys(v)
    table.sort(keys)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = nxt .. string.format("%q", k) .. ": " .. encode(v[k], nxt)
    end
    if #parts == 0 then
      return "{}"
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return "null"
end

local o = assert(io.open(out, "w"))
o:write(encode(data, "") .. "\n")
o:close()
