-- Spike H0.1b — what nvim and its child processes see (test 5).
-- Run as: SPIKE_NVIM_OUT=<file> nvim --headless -c "luafile nvim-check.lua"
-- (nvim is the .ditto/bin wrapper; its init.lua sets vim.o.shell = .host-sh)
local out = assert(io.open(assert(os.getenv("SPIKE_NVIM_OUT")), "w"))
local root = vim.env.XDG_CONFIG_HOME and vim.fn.fnamemodify(vim.env.XDG_CONFIG_HOME, ":h") or ""

local function trim(s)
  return ((s or ""):gsub("[\r\n]+", " "):gsub("%s+$", ""))
end

local function put(k, v)
  out:write(k .. "=" .. trim(tostring(v)) .. "\n")
end

local function readfile(p)
  local f = io.open(p, "r")
  if not f then
    return "<missing>"
  end
  local s = f:read("*a")
  f:close()
  return s
end

local xdg_cmd = "env | grep '^XDG_' | sort | tr '\\n' ' '"
-- ssh only with the fixture (docker.sh): it reads ~/.ssh/config of the
-- passwd home, not $HOME, so elsewhere it would read the real one.
local ssh_cmd = os.getenv("SPIKE_SSH_FIXTURE") == "1" and "ssh -G ditto-fixture 2>/dev/null | grep '^user '"
  or "echo skipped"

-- Inside nvim: XDG_* point into .ditto (only here).
put("nvim_xdg_config", vim.env.XDG_CONFIG_HOME)
put("nvim_stdpath_data", vim.fn.stdpath("data"))
put("nvim_shell", vim.o.shell)

-- :! and system() with a string go through 'shell' (= .host-sh).
put("bang_xdg", vim.fn.system(xdg_cmd))
put("bang_git", vim.fn.system("git config --global user.name"))
put("bang_ssh", vim.fn.system(ssh_cmd))

-- system() with a list execs directly with nvim's env (gitsigns -> git).
put("list_git", vim.fn.system({ "git", "config", "--global", "user.name" }))
-- Control: the same without the GIT_CONFIG_GLOBAL the wrapper adds.
put("list_git_without_gcg", vim.fn.system({ "env", "-u", "GIT_CONFIG_GLOBAL", "git", "config", "--global", "user.name" }))
put("git_version", vim.fn.system({ "git", "--version" }))
-- Alternative to GIT_CONFIG_GLOBAL (git >= 2.32 only): a git/config in
-- nvim's XDG_CONFIG_HOME that includes the user's. git reads it together
-- with ~/.gitconfig, on any version with [include] (1.7.10+).
local inc = root .. "/cache/xdg-include"
vim.fn.mkdir(inc .. "/git", "p")
local f = assert(io.open(inc .. "/git/config", "w"))
f:write("[include]\n\tpath = ~/.config/git/config\n")
f:close()
-- (`git config --global` skips includes unless --includes; git commit,
-- log… follow them.)
put("list_git_include", vim.fn.system({ "env", "-u", "GIT_CONFIG_GLOBAL", "XDG_CONFIG_HOME=" .. inc, "git", "config", "--includes", "--global", "user.name" }))

-- :terminal runs 'shell' too.
local tmp = root .. "/cache/spike-term"
vim.cmd(
  "terminal "
    .. xdg_cmd .. " > " .. tmp .. ".xdg; "
    .. "git config --global user.name > " .. tmp .. ".git; "
    .. ssh_cmd .. " > " .. tmp .. ".ssh"
)
vim.fn.jobwait({ vim.b.terminal_job_id }, 15000)
put("term_xdg", readfile(tmp .. ".xdg"))
put("term_git", readfile(tmp .. ".git"))
put("term_ssh", readfile(tmp .. ".ssh"))

-- lazygit integrated (Snacks.lazygit / lazygit.nvim run `lazygit` from PATH,
-- i.e. the .ditto/bin wrapper). -cd prints the config dir lazygit resolved
-- (XDG_CONFIG_HOME leaked -> it would be under .ditto/config).
put("lazygit_cd", vim.fn.system({ "lazygit", "-cd" }))
put("lazygit_path", vim.fn.exepath("lazygit"))
-- What lazygit (and the git it spawns) receives: the restore block shared by
-- every wrapper, then the command.
put("wrapped_xdg", vim.fn.system({ root .. "/bin/.probe", "sh", "-c", xdg_cmd }))
put("wrapped_git", vim.fn.system({ root .. "/bin/.probe", "git", "config", "--global", "user.name" }))
put("wrapped_ssh", vim.fn.system({ root .. "/bin/.probe", "sh", "-c", ssh_cmd }))
put("wrapped_gcg", vim.fn.system({ root .. "/bin/.probe", "sh", "-c", "echo ${GIT_CONFIG_GLOBAL-unset}" }))

out:close()
vim.cmd("qa!")
