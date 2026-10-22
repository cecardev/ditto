-- Spike H0.5 — opens one file per language in the user's LazyVim (through the
-- nvim wrapper, headless) and checks that its LSP starts, initializes and
-- answers textDocument/documentSymbol.
--
--   nvim --headless "+luafile lsp-check.lua"
--
-- Env: H05_PROJ (sample project), H05_REPORT (JSON), H05_LSP_TIMEOUT (ms per
-- server), H05_ONLY (one file name). Prints "CASE file|server|status|ms|detail".

local proj = assert(os.getenv("H05_PROJ"), "H05_PROJ")
local report_path = os.getenv("H05_REPORT")
local timeout = tonumber(os.getenv("H05_LSP_TIMEOUT") or "") or 120000
local only = os.getenv("H05_ONLY")

local cases = {
  { file = "main.lua", servers = { "lua_ls" } },
  { file = "main.py", servers = { "pyright", "basedpyright" } },
  { file = "main.go", servers = { "gopls" } },
  { file = "main.ts", servers = { "vtsls", "ts_ls", "tsc" } },
}

local results = {}
for _, c in ipairs(cases) do
  if not only or only == c.file then
    local t0 = vim.uv.hrtime()
    vim.cmd.edit(vim.fn.fnameescape(proj .. "/" .. c.file))
    local buf = vim.api.nvim_get_current_buf()
    local client
    local ok = vim.wait(timeout, function()
      for _, cl in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
        if vim.tbl_contains(c.servers, cl.name) and cl.initialized then
          client = cl
          return true
        end
      end
      return false
    end, 200)
    local r = { file = c.file, ms = math.floor((vim.uv.hrtime() - t0) / 1e6) }
    if ok then
      r.server = client.name
      local version = client.server_info and client.server_info.version
      -- gopls reports its whole build info as JSON: keep the module version.
      version = version and (tostring(version):match('"Main":{[^}]-"Version":"([^"]+)"') or version)
      local resp = client:request_sync(
        "textDocument/documentSymbol",
        { textDocument = vim.lsp.util.make_text_document_params(buf) },
        timeout,
        buf
      )
      if resp and resp.result then
        r.status = "PASS"
        r.detail = ("%d symbols; server %s"):format(#resp.result, tostring(version or "?"))
      else
        r.status = "FAIL"
        r.detail = "documentSymbol: " .. vim.inspect(resp and resp.err or "no response"):gsub("\n", " ")
      end
    else
      local names = {}
      for _, cl in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
        names[#names + 1] = cl.name
      end
      r.status = "FAIL"
      r.server = table.concat(c.servers, "/")
      r.detail = "no initialized client (attached: " .. (#names > 0 and table.concat(names, ",") or "none") .. ")"
    end
    results[#results + 1] = r
    io.stdout:write(("CASE %s|%s|%s|%d|%s\n"):format(r.file, r.server or "-", r.status, r.ms, r.detail or ""))
  end
end

if report_path then
  local f = assert(io.open(report_path, "w"))
  f:write(vim.json.encode(results))
  f:close()
end
vim.cmd("qall!")
