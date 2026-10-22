#!/bin/sh
# Fake local MCP server: records the environment OpenCode gives its child
# processes, then exits (the MCP handshake fails on purpose).
env | grep -E '^(XDG_|OPENCODE|DITTO|HOME=|TMPDIR=|PATH=|SHELL=|BUN)' | sort >"$1"
exit 0
