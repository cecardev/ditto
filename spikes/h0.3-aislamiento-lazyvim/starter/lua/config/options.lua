-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- ditto (arch.md §8): every shell Neovim starts (:terminal, :!, system() with
-- a string, Snacks terminal) goes through .host-sh, which restores the host
-- environment saved by the nvim wrapper. DITTO_ROOT is exported by the
-- wrapper; outside ditto the default shell is kept.
if vim.env.DITTO_ROOT and vim.uv.fs_stat(vim.env.DITTO_ROOT .. "/bin/.host-sh") then
  vim.o.shell = vim.env.DITTO_ROOT .. "/bin/.host-sh"
end
