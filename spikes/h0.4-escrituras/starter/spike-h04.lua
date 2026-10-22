-- Spike H0.4: replaces H0.3's spike-offline.lua in this spike's copy of the
-- starter. Mason is enabled (the session installs one small package by hand,
-- `:MasonInstall stylua@<pinned>`), but nothing is installed automatically:
-- every download of the session is either pinned or cross-checked by sha256
-- (run.sh). Parsers and the blink.cmp binary stay off, as in H0.3 (H0.5).
-- lib.sh replaces @H04_MASON_REGISTRY@ with the pinned registry release.
return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.registries = { "github:mason-org/mason-registry@@H04_MASON_REGISTRY@" }
      -- LazyVim (and the extras) would install stylua, shfmt, ruff... here.
      opts.ensure_installed = {}
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- No server is installed through mason-lspconfig (lua_ls, pyright...).
      for name, server in pairs(opts.servers or {}) do
        if type(server) == "table" then
          server.mason = false
        elseif server == true then
          opts.servers[name] = { mason = false }
        end
      end
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
  { "saghen/blink.cmp", opts = { fuzzy = { implementation = "lua" } } },
}
