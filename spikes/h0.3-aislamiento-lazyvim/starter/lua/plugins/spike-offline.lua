-- Spike H0.3 only: keep the first start free of downloads that are not pinned
-- by lazy-lock.json or verified by sha256, so this spike measures isolation and
-- nothing else. H0.5 (#7) owns Mason and parsers: delete this file there.
return {
  -- Mason would fetch its registry and the extras' LSPs/formatters (H0.5).
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  -- nvim-treesitter would download parser sources (tarballs, no sha256) and
  -- compile them with tree-sitter + cc (H0.5).
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
  -- blink.cmp would download its prebuilt Rust fuzzy matcher.
  { "saghen/blink.cmp", opts = { fuzzy = { implementation = "lua" } } },
}
