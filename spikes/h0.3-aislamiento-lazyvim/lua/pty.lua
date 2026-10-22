-- Spike H0.3 — drives an interactive program in a pseudo-terminal, without a
-- real TTY. Used to run the bash/zsh session and the nvim under test as a user
-- would. Reusable by #6/#7.
--
--   nvim --clean --headless -n -i NONE -l pty.lua <env-file> <cwd> <steps> <transcript> <cmd> [args...]
--
-- <env-file>: KEY=VALUE per line; the child gets exactly this environment
--   (clear_env), so nothing of the driver (or of the caller) leaks in.
-- <steps>: one action per line:
--   send <text>          write <text> followed by CR
--   key <lua-escaped>    write raw bytes, e.g. key \24 (Ctrl-X)
--   wait <file> <ms>     until <file> exists (fails the run on timeout)
--   sleep <ms>
--   exit <ms>            until the child exits (killed on timeout)
-- Exit code: 0 if every wait succeeded and the child exited.
local envfile, cwd, steps, transcript = arg[1], arg[2], arg[3], arg[4]
local cmd = {}
for i = 5, #arg do
  cmd[#cmd + 1] = arg[i]
end
assert(#cmd > 0, "usage: pty.lua <env-file> <cwd> <steps> <transcript> <cmd> [args...]")

local env = {}
for line in io.lines(envfile) do
  local k, v = line:match("^([%w_]+)=(.*)$")
  if k then
    env[k] = v
  end
end

local out = assert(io.open(transcript, "w"))
local exited, code = false, nil
local job = vim.fn.jobstart(cmd, {
  pty = true,
  width = 200,
  height = 50,
  cwd = cwd,
  env = env,
  clear_env = true,
  on_stdout = function(_, data)
    out:write(table.concat(data, "\n"))
    out:flush()
  end,
  on_exit = function(_, c)
    exited, code = true, c
  end,
})
assert(job > 0, "jobstart failed: " .. table.concat(cmd, " "))

local ok = true
local function log(msg)
  io.stderr:write("[pty] " .. msg .. "\n")
end

for line in io.lines(steps) do
  local op, rest = line:match("^(%S+)%s*(.*)$")
  if op == "send" then
    vim.fn.chansend(job, rest .. "\r")
  elseif op == "key" then
    vim.fn.chansend(job, (load("return '" .. rest .. "'"))())
  elseif op == "wait" then
    local file, ms = rest:match("^(.-)%s+(%d+)$")
    if not vim.wait(tonumber(ms), function()
      return vim.uv.fs_stat(file) ~= nil
    end, 100) then
      log("timeout waiting for " .. file)
      ok = false
    end
  elseif op == "sleep" then
    vim.wait(tonumber(rest), function()
      return false
    end, 100)
  elseif op == "exit" then
    if not vim.wait(tonumber(rest), function()
      return exited
    end, 100) then
      log("child did not exit; killing it")
      vim.fn.jobstop(job)
      ok = false
    end
  elseif op and not op:match("^#") then
    log("unknown step: " .. line)
    ok = false
  end
end

if not exited then
  vim.fn.jobstop(job)
  vim.wait(2000, function()
    return exited
  end, 100)
end
out:close()
log(("child exit code %s"):format(tostring(code)))
os.exit(ok and exited and 0 or 1)
