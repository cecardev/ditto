-- Spike H0.3 — dumps what LazyVim did with lazyvim.json and quits:
--
--   DITTO_SPIKE_ORDER_OUT=<out.json> nvim --headless "+lua dofile('<spike>/lua/extras-order.lua')"
--
-- Output: the lazy.nvim import order (spec.modules), the extras LazyVim read,
-- notifications/messages (import-order warning, unknown extras...).
local outfile = assert(vim.env.DITTO_SPIKE_ORDER_OUT, "DITTO_SPIKE_ORDER_OUT")
-- Capture vim.notify before VeryLazy: LazyVim queues startup notifications
-- and replays them through whatever vim.notify is current afterwards. Capture
-- only: forwarding to LazyVim's queueing notify would append to the list it is
-- replaying and loop forever.
local captured = {}
vim.notify = function(msg, level, opts)
  captured[#captured + 1] = { msg = tostring(msg), level = level, title = type(opts) == "table" and opts.title or nil }
end
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
vim.wait(1500, function()
  return false
end)
local report = {
  modules = require("lazy.core.config").spec.modules,
  extras_json = LazyVim.config.json.data.extras,
  notifications = {},
  notify_calls = captured,
  messages = vim.api.nvim_exec2("messages", { output = true }).output,
}
local ok, hist = pcall(function()
  return Snacks.notifier.get_history()
end)
if ok then
  for _, n in ipairs(hist or {}) do
    report.notifications[#report.notifications + 1] = { level = n.level, msg = n.msg, title = n.title }
  end
end
local f = assert(io.open(outfile, "w"))
f:write(vim.json.encode(report))
f:close()
vim.cmd("qa!")
