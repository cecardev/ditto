#!/bin/sh
# Spike H0.1 — generates the shared mise.lock (checksums for every platform)
# from the superset config, using an isolated mise in a scratch .ditto/.
#
#   sh gen-lock.sh <scratch-dir> [output-lock]
#
# Needs network (GitHub API). Writes nothing outside <scratch-dir> except the
# output lock (default: mise.lock next to this script).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd -P)
. "$HERE/env.sh"

[ $# -ge 1 ] || { echo "usage: $0 <scratch-dir> [output-lock]" >&2; exit 2; }
OUT=${2:-$HERE/mise.lock}
PLATFORMS="linux-x64,linux-arm64,linux-x64-musl,linux-arm64-musl,macos-x64,macos-arm64"

ditto_mise_paths "$1/.ditto"
ditto_mise_bootstrap
CFG="$DITTO_MISE_CONFIG"
LOCK="$DITTO_MISE_LOCK"
rm -f "$LOCK"

# Pass 1: every tool, normal OpenCode build, all platforms.
ditto_write_config "$CFG" all normal
ditto_mise lock --global --platform "$PLATFORMS"

# Pass 2/3: OpenCode -baseline (x86_64 without AVX2), glibc and musl. Tool
# options are part of the lock entry, so these coexist with pass 1. Locking a
# single tool does not prune the others.
ditto_write_config "$CFG" all baseline glibc
ditto_mise lock --global --platform linux-x64 github:anomalyco/opencode
ditto_write_config "$CFG" all baseline musl
ditto_mise lock --global --platform linux-x64-musl github:anomalyco/opencode

cp "$LOCK" "$OUT"
echo "wrote $OUT" >&2
