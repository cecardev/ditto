-- Spike H0.5 — what the children of Neovim see, inside the user's LazyVim
-- (through the nvim wrapper, headless):
--   <report>-shell.txt     H05_PROBE through 'shell' (.host-sh), like `:!`
--   <report>-argv.txt      H05_PROBE as an argument-list child, like Mason
--   <report>-config.txt    npm/pip/go config and caches, argument-list child
--   <report>-shellcfg.txt  the cache variables, through 'shell'
--
--   nvim --headless "+luafile rt-probe.lua"
-- Env: H05_REPORT (path prefix), H05_PROBE (sh snippet).

local prefix = assert(os.getenv("H05_REPORT"), "H05_REPORT")
local probe = assert(os.getenv("H05_PROBE"), "H05_PROBE")

local function write(name, text)
  local f = assert(io.open(prefix .. "-" .. name .. ".txt", "w"))
  f:write(text)
  f:close()
end

-- 'shell' = $DITTO_ROOT/bin/.host-sh (options.lua): restores the host env.
write("shell", vim.fn.system(probe))
-- Argument list: inherits nvim's environment (wrapper PATH, XDG_*, caches).
write("argv", vim.system({ "sh", "-c", probe }, { text = true }):wait().stdout or "")

local config = [[
printf 'pip-config=%s\n' "$(pip3 config list 2>&1 | tr '\n' ' ')"
printf 'pip-files=%s\n' "$(pip3 config debug 2>&1 | grep -E 'exists: True' -B0 | tr '\n' ' ')"
printf 'pip-cache=%s\n' "$(python3 -m pip cache dir 2>&1)"
printf 'npm-fetch-retries=%s\n' "$(npm config get fetch-retries 2>/dev/null)"
printf 'npm-cache=%s\n' "$(npm config get cache 2>/dev/null)"
printf 'npm-warn=%s\n' "$(npm config get cache 2>&1 >/dev/null | tr '\n' ' ')"
for v in GOENV GOPRIVATE GOPATH GOMODCACHE GOCACHE GOTOOLCHAIN GOPROXY; do
  printf '%s=%s\n' "$v" "$(go env "$v" 2>&1)"
done
]]
write("config", vim.system({ "sh", "-c", config }, { text = true }):wait().stdout or "")

write(
  "shellcfg",
  vim.fn.system(
    'for v in npm_config_cache PIP_CACHE_DIR GOPATH GOMODCACHE GOCACHE GOTOOLCHAIN GOENV XDG_CONFIG_HOME; do eval "printf \'%s=%s\\n\' $v \\"\\${$v-unset}\\""; done'
  )
)
vim.cmd("qall!")
