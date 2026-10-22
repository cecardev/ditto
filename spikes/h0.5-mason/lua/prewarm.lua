-- Spike H0.5 — headless prewarm of a LazyVim config, run through the nvim
-- wrapper after `Lazy! restore`:
--
--   nvim --headless "+luafile prewarm.lua"
--
-- It downloads, and WAITS for, everything LazyVim would otherwise fetch on
-- the first interactive start:
--   1. nvim-treesitter parsers of opts.ensure_installed (download + compile);
--   2. the blink.cmp prebuilt fuzzy matcher;
--   3. Mason packages: mason.nvim opts.ensure_installed + the LSP servers that
--      LazyVim's lspconfig would hand to mason-lspconfig (same rules as
--      lazyvim/plugins/lsp/init.lua) + mason-lspconfig opts.ensure_installed.
--
-- Loading mason.nvim/nvim-lspconfig makes LazyVim start its own async
-- installs; `:MasonInstall` in headless mode skips a package that is already
-- installing instead of waiting for it, so this script waits on the registry
-- state instead. Exit code: 0 if every step succeeded, 1 otherwise.
-- Env: H05_REPORT (JSON report path), H05_TIMEOUT_MS (default 45 min).
-- Throwaway spike code: in ditto this is embedded and run by `ditto setup`.

local report_path = os.getenv("H05_REPORT")
local timeout = tonumber(os.getenv("H05_TIMEOUT_MS") or "") or 45 * 60 * 1000
local report = { steps = {}, mason = {}, parsers = {} }
local failed = false

local function ms_since(t)
  return math.floor((vim.uv.hrtime() - t) / 1e6)
end

local function log(msg)
  io.stdout:write("[prewarm] " .. msg .. "\n")
end

local function step(name, fn)
  local t = vim.uv.hrtime()
  local ok, err = pcall(fn)
  report.steps[#report.steps + 1] = { name = name, ok = ok, err = (not ok) and tostring(err) or nil, ms = ms_since(t) }
  log(("%s: %s in %d ms%s"):format(name, ok and "ok" or "FAILED", ms_since(t), ok and "" or (" — " .. tostring(err))))
  if not ok then
    failed = true
  end
end

local function finish()
  local parts = {}
  for _, s in ipairs(report.steps) do
    parts[#parts + 1] = ("%s %s %.1fs"):format(s.name, s.ok and "ok" or "FAIL", s.ms / 1000)
  end
  report.summary = table.concat(parts, ", ")
  if report_path then
    local f = assert(io.open(report_path, "w"))
    f:write(vim.json.encode(report))
    f:close()
  end
  vim.cmd(failed and "cquit 1" or "qall!")
end

-- 1. Treesitter parsers. Loading nvim-treesitter makes LazyVim start its own
-- async install of the same list; the two can collide on the download dir
-- (seen on macOS: "Could not rename temp: ENOTEMPTY"), so missing parsers are
-- retried once after the first pass.
step("parsers", function()
  require("lazy").load({ plugins = { "nvim-treesitter" } })
  local langs = LazyVim.opts("nvim-treesitter").ensure_installed or {}
  local TS = require("nvim-treesitter")
  local function missing()
    local have = {}
    for _, l in ipairs(TS.get_installed("parsers")) do
      have[l] = true
    end
    return vim.tbl_filter(function(l)
      return not have[l]
    end, langs)
  end
  TS.install(langs, { summary = true }):wait(timeout)
  local first = missing()
  if #first > 0 then
    log("retrying parsers: " .. table.concat(first, ","))
    TS.install(first, { summary = true }):wait(timeout)
  end
  local left = missing()
  report.parsers = { wanted = langs, retried = first, missing = left }
  assert(#left == 0, "missing parsers: " .. table.concat(left, ","))
end)

-- 2. blink.cmp prebuilt binary.
-- Loading blink.cmp runs its setup, which starts the same download
-- asynchronously; a concurrent ensure_downloaded() sees the half-written
-- version file and falls back to Lua. So retry until the setup's download
-- has finished (ensure_downloaded then only verifies the sha256).
step("blink", function()
  require("lazy").load({ plugins = { "blink.cmp" } })
  local res_err, impl
  for attempt = 1, 5 do
    local done = false
    require("blink.cmp.fuzzy.download").ensure_downloaded(function(err, implementation)
      done, res_err, impl = true, err, implementation
    end)
    assert(vim.wait(timeout, function()
      return done
    end, 200), "timeout")
    report.blink = { implementation = impl, err = res_err, attempts = attempt }
    if impl == "rust" then
      break
    end
    vim.wait(3000)
  end
  assert(res_err == nil, tostring(res_err))
  assert(impl == "rust", "fell back to " .. tostring(impl))
end)

-- 3. Mason packages.
step("mason", function()
  local wanted, seen = {}, {}
  local function want(name)
    if name and not seen[name] then
      seen[name] = true
      wanted[#wanted + 1] = name
    end
  end
  for _, p in ipairs(LazyVim.opts("mason.nvim").ensure_installed or {}) do
    want(p)
  end
  require("lazy").load({ plugins = { "mason.nvim", "mason-lspconfig.nvim" } })
  local map = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
  local servers = LazyVim.opts("nvim-lspconfig").servers or {}
  for name, sopts in pairs(servers) do
    if name ~= "*" then
      sopts = sopts == true and {} or (not sopts) and { enabled = false } or sopts
      if sopts.enabled ~= false and sopts.mason ~= false and map[name] then
        want(map[name])
      end
    end
  end
  for _, s in ipairs(LazyVim.opts("mason-lspconfig.nvim").ensure_installed or {}) do
    want(map[s] or s)
  end
  table.sort(wanted)
  log("mason packages: " .. table.concat(wanted, " "))

  local registry = require("mason-registry")
  local failures = {}
  registry:on("package:install:failed", function(pkg, err)
    failures[pkg.name] = tostring(err)
  end)
  -- Let LazyVim's lspconfig config run too (it starts mason-lspconfig's
  -- installs): this is what a first interactive start would do.
  require("lazy").load({ plugins = { "nvim-lspconfig" } })

  local refreshed = false
  registry.refresh(function()
    refreshed = true
  end)
  assert(vim.wait(5 * 60 * 1000, function()
    return refreshed
  end, 100), "registry refresh timeout")

  local t0 = vim.uv.hrtime()
  -- Our own installs report through their callback; the ones LazyVim already
  -- started are awaited and, if they did not end installed, run once more
  -- with a callback so that their error is recorded too.
  local pending = 0
  local function install(pkg)
    pending = pending + 1
    pkg:install({}, function(ok, err)
      pending = pending - 1
      if not ok then
        failures[pkg.name] = tostring(err)
      end
    end)
  end
  local function installing()
    for _, name in ipairs(wanted) do
      if registry.get_package(name):is_installing() then
        return true
      end
    end
    return false
  end
  for pass = 1, 2 do
    for _, name in ipairs(wanted) do
      local pkg = registry.get_package(name)
      if not pkg:is_installed() and not pkg:is_installing() and (pass == 1 or not failures[name]) then
        install(pkg)
      end
    end
    -- Mason queues installs (max_concurrent_installers): wait for every
    -- callback and for every package still installing.
    assert(vim.wait(timeout, function()
      return pending == 0 and not installing()
    end, 500), "timeout waiting for Mason")
  end
  report.mason.ms = ms_since(t0)
  report.mason.wanted = wanted
  report.mason.failures = failures
  local missing = {}
  for _, name in ipairs(wanted) do
    if not registry.get_package(name):is_installed() then
      missing[#missing + 1] = name
    end
  end
  report.mason.missing = missing
  local reg = {}
  for _, src in ipairs(registry.sources and registry.sources:to_list() or {}) do
    reg[#reg + 1] = src:get_display_name()
  end
  report.mason.registry = reg
  assert(#missing == 0, "not installed: " .. table.concat(missing, ",") .. " " .. vim.inspect(failures))
end)

finish()
