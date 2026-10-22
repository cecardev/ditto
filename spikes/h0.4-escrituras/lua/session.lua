-- Spike H0.4 — the Neovim part of the session script, run inside the real
-- (TUI) nvim started from the session shell, in a pty:
--
--   nvim "+lua dofile('<spike>/lua/session.lua')"
--
-- Environment: H04_OUT (results dir), H04_TAG (prefix). cwd = the project repo.
-- Steps, once LazyVim is fully loaded (VeryLazy): edit a Lua file, format it
-- with conform + the Mason-installed stylua, save it; `:!git status`;
-- `:terminal`; the Snacks terminal; lazygit (Snacks.lazygit). Then writes
-- <out>/<tag>-nvim.json and quits (shada etc. are written on exit as usual).
local out = assert(vim.env.H04_OUT, "H04_OUT")
local tag = vim.env.H04_TAG or "s"
local repo = vim.fn.getcwd()
local report = { steps = {} }

local function path(name)
  return out .. "/" .. tag .. "-" .. name
end

local function wait_file(p, ms)
  return vim.wait(ms or 20000, function()
    return vim.uv.fs_stat(p) ~= nil
  end, 100)
end

local function step(name, fn)
  local ok, err = pcall(fn)
  report.steps[#report.steps + 1] = { name = name, ok = ok, err = err and tostring(err) or nil }
end

-- Records the environment the shell sees (TMPDIR, npm_config_cache, XDG_*
-- must be the host's), then exits.
local function in_term(job, name)
  vim.fn.chansend(
    job,
    "env | LC_ALL=C sort > "
      .. vim.fn.shellescape(path(name .. ".env"))
      .. "; echo "
      .. name
      .. " > "
      .. vim.fn.shellescape(path(name .. ".done"))
      .. "; exit\r"
  )
  assert(wait_file(path(name .. ".done")), name .. ": no marker")
end

local function run()
  report.shell = vim.o.shell
  report.stdpath = {
    config = vim.fn.stdpath("config"),
    data = vim.fn.stdpath("data"),
    state = vim.fn.stdpath("state"),
    cache = vim.fn.stdpath("cache"),
    run = vim.fn.stdpath("run"),
  }
  report.servername = vim.v.servername
  report.stylua = vim.fn.exepath("stylua")

  step("edit-format-save", function()
    vim.cmd("edit " .. vim.fn.fnameescape(repo .. "/hello.lua"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local   x  =  { 1,2,3 }", "return   x" })
    report.formatted = require("conform").format({ async = false, timeout_ms = 15000, lsp_format = "never" })
    report.text = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    vim.cmd("write")
  end)

  step("bang", function()
    vim.cmd("silent !git status --short > " .. vim.fn.shellescape(path("bang.done")))
  end)

  step("terminal", function()
    vim.cmd("terminal")
    in_term(vim.b.terminal_job_id, "terminal")
  end)

  step("snacks-terminal", function()
    local term = Snacks.terminal.open(nil, { cwd = repo })
    in_term(vim.b[term.buf].terminal_job_id, "snacks")
  end)

  step("lazygit", function()
    local term = Snacks.lazygit({ cwd = repo })
    local job = vim.b[term.buf].terminal_job_id
    vim.wait(5000, function()
      return false
    end)
    report.lazygit_screen = vim.api.nvim_buf_get_lines(term.buf, 0, 8, false)
    vim.fn.chansend(job, "q")
    vim.wait(3000, function()
      return vim.fn.jobwait({ job }, 0)[1] ~= -1
    end, 100)
  end)

  local f = assert(io.open(path("nvim.json"), "w"))
  f:write(vim.json.encode(report))
  f:close()
  vim.cmd("qa!")
end

vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function()
    -- Let the deferred VeryLazy handlers (keymaps, gitsigns...) settle.
    vim.defer_fn(run, 1500)
  end,
})
