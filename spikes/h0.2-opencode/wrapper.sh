#!/bin/sh
# Prototype of the generated .ditto/bin/opencode wrapper (spike H0.2, #2).
# ditto would inline DITTO_ROOT handling and the absolute binary path; here
# they come from the environment so probe.sh can reuse it.
set -eu
: "${DITTO_ROOT:?DITTO_ROOT not set}"
: "${DITTO_OPENCODE_BIN:?DITTO_OPENCODE_BIN not set}"

# Keep the caller's XDG so .host-sh (shell tool) can restore it (arch.md §8).
export DITTO_ORIG_XDG_CONFIG_HOME="${XDG_CONFIG_HOME-}"
export DITTO_ORIG_XDG_DATA_HOME="${XDG_DATA_HOME-}"
export DITTO_ORIG_XDG_STATE_HOME="${XDG_STATE_HOME-}"
export DITTO_ORIG_XDG_CACHE_HOME="${XDG_CACHE_HOME-}"
export DITTO_ORIG_TMPDIR="${TMPDIR-}"

# OpenCode only reads XDG_* for data/state/cache (auth.json lives in data);
# OPENCODE_CONFIG_DIR alone does not stop it from creating ~/.config/opencode.
export XDG_CONFIG_HOME="$DITTO_ROOT/config"
export XDG_DATA_HOME="$DITTO_ROOT/data"
export XDG_STATE_HOME="$DITTO_ROOT/state"
export XDG_CACHE_HOME="$DITTO_ROOT/cache"
export OPENCODE_CONFIG_DIR="$DITTO_ROOT/config/opencode"
# os.tmpdir()/opencode would otherwise land in the system temp dir.
export TMPDIR="$DITTO_ROOT/tmp"
# ditto pins the version in mise.lock; no self-update checks.
export OPENCODE_DISABLE_AUTOUPDATE=1

exec "$DITTO_OPENCODE_BIN" "$@"
