-- Spike H0.3 — runs inside the nvim under test (LazyVim, started through the
-- .ditto/bin/nvim wrapper from the session shell):
--
--   nvim --headless "+lua dofile('<spike>/lua/probe.lua')"
--
-- Environment: DITTO_SPIKE_PROBE (probe.sh), DITTO_SPIKE_OUT (results dir),
-- DITTO_SPIKE_REPO (git repo), DITTO_SPIKE_TAG (prefix for the contexts).
-- Every child context runs probe.sh; the interactive ones (:terminal, Snacks
-- terminal, lazygit) get the command typed into their pty with chansend.
-- Writes <out>/<tag>-nvim.json with what nvim itself reports and quits.
local probe = assert(vim.env.DITTO_SPIKE_PROBE, "DITTO_SPIKE_PROBE")
local out = assert(vim.env.DITTO_SPIKE_OUT, "DITTO_SPIKE_OUT")
local repo = assert(vim.env.DITTO_SPIKE_REPO, "DITTO_SPIKE_REPO")
local tag = vim.env.DITTO_SPIKE_TAG or "nvim"
local report = { cases = {} }

local function ctx(name)
  return tag .. "-" .. name
end

local function done(name)
  return vim.uv.fs_stat(out .. "/" .. ctx(name) .. "/done") ~= nil
end

local function wait_done(name, ms)
  return vim.wait(ms or 30000, function()
    return done(name)
  end, 100)
end

local function shline(name)
  return table.concat({
    "sh",
    vim.fn.shellescape(probe),
    ctx(name),
    vim.fn.shellescape(out),
    vim.fn.shellescape(repo),
  }, " ")
end

local function case(name, fn)
  local ok, err = pcall(fn)
  report.cases[name] = { ok = ok and done(name), err = err and tostring(err) or nil }
end

-- LazyVim finishes its setup on VeryLazy, which needs a UI; trigger it so the
-- headless instance is configured as an interactive one.
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
vim.wait(1500, function()
  return false
end)

report.shell = vim.o.shell
report.stdpath = {
  config = vim.fn.stdpath("config"),
  data = vim.fn.stdpath("data"),
  state = vim.fn.stdpath("state"),
  cache = vim.fn.stdpath("cache"),
}
report.exepath = {
  git = vim.fn.exepath("git"),
  lazygit = vim.fn.exepath("lazygit"),
  nvme = vim.fn.exepath("nvme"),
  rt = vim.fn.exepath("ditto-rt"),
}

-- 1. :terminal (shell = .host-sh without arguments -> session shell).
case("terminal", function()
  vim.cmd("terminal")
  local job = vim.b.terminal_job_id
  vim.fn.chansend(job, shline("terminal") .. "; exit\r")
  wait_done("terminal")
end)

-- 2. :!cmd (.host-sh -c cmd).
case("bang", function()
  vim.cmd("silent !" .. shline("bang"))
end)

-- 3. system() with a string (.host-sh -c cmd).
case("system", function()
  vim.fn.system(shline("system"))
end)

-- 4. Argument list (gitsigns, lazy.nvim, vim.system): no shell involved, the
-- child inherits nvim's own environment.
case("list", function()
  vim.system({ "sh", probe, ctx("list"), out, repo }):wait()
end)

-- 5. Snacks terminal (shell = .host-sh without arguments).
case("snacks", function()
  local term = Snacks.terminal.open(nil, { cwd = repo })
  local job = vim.b[term.buf].terminal_job_id
  vim.fn.chansend(job, shline("snacks") .. "; exit\r")
  wait_done("snacks")
end)

-- 6. lazygit integrated (Snacks.lazygit -> .ditto/bin/lazygit). The probe is
-- a lazygit custom command bound to <ctrl+x> in .ditto/config/lazygit.
case("lazygit", function()
  local term = Snacks.lazygit({ cwd = repo })
  local job = vim.b[term.buf].terminal_job_id
  report.lg_config_file = vim.env.LG_CONFIG_FILE
  vim.wait(4000, function()
    return false
  end)
  vim.fn.chansend(job, "\24")
  wait_done("lazygit", 15000)
  vim.fn.chansend(job, "q")
  report.lazygit_screen = vim.api.nvim_buf_get_lines(term.buf, 0, 12, false)
end)

-- 7. gitsigns really attaches in this session (it runs git by argument list).
case("gitsigns", function()
  vim.cmd("edit " .. vim.fn.fnameescape(repo .. "/README.md"))
  vim.cmd("doautocmd BufReadPost")
  local ok = vim.wait(10000, function()
    return vim.b.gitsigns_head ~= nil
  end, 100)
  report.gitsigns = { attached = ok, head = vim.b.gitsigns_head }
  vim.system({ "sh", probe, ctx("gitsigns"), out, repo }):wait()
end)

-- 8. Extras: import order seen by lazy.nvim, extras LazyVim read, warnings.
local modules = require("lazy.core.config").spec.modules
report.modules = modules
report.extras_json = LazyVim.config.json.data.extras
local okh, hist = pcall(function()
  return Snacks.notifier.get_history()
end)
report.notifications = {}
if okh then
  for _, n in ipairs(hist or {}) do
    report.notifications[#report.notifications + 1] = { level = n.level, msg = n.msg, title = n.title }
  end
end
report.messages = vim.api.nvim_exec2("messages", { output = true }).output

local f = assert(io.open(out .. "/" .. tag .. "-nvim.json", "w"))
f:write(vim.json.encode(report))
f:close()
vim.cmd("qa!")
