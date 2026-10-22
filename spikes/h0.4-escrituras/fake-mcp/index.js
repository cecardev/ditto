#!/usr/bin/env node
// Spike H0.4: fake local MCP server started by OpenCode through npx. Records
// the environment it receives (what matters for writes) and exits, so the MCP
// handshake fails on purpose. No package is downloaded (local folder), no dependencies.
const fs = require("fs");
const keep = /^(XDG_|OPENCODE|DITTO|HOME$|TMPDIR$|PATH$|npm_config_|SHELL$)/;
const lines = Object.keys(process.env)
  .filter((k) => keep.test(k))
  .sort()
  .map((k) => `${k}=${process.env[k]}`);
fs.writeFileSync(process.argv[2] || "/dev/stdout", lines.join("\n") + "\n");
process.exit(0);
