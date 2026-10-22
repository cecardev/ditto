-- ditto (H0.5): Mason, nvim-treesitter and blink.cmp keep their LazyVim
-- defaults, except the Mason registry, which is pinned to one release of
-- mason-org/mason-registry. That fixes the version of every package (the
-- registry entry names it: pkg:npm/pyright@1.1.414, pkg:golang/...gopls@v0.23.0)
-- and avoids the unauthenticated GitHub API call that resolves "latest"
-- (60 requests/hour). ditto would write the tag it validated; `ditto update`
-- moves it. H05_MASON_REGISTRY=latest restores Mason's default (spike only).
local registry = vim.env.H05_MASON_REGISTRY or "github:mason-org/mason-registry@2026-10-22-ill-fund"

return {
  {
    "mason-org/mason.nvim",
    opts = {
      registries = registry ~= "latest" and { registry } or nil,
      -- Spike only: DEBUG logs every URL Mason fetches (mason.log).
      log_level = vim.log.levels.DEBUG,
    },
  },
}
