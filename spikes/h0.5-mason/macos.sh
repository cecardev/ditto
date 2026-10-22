#!/bin/sh
# Spike H0.5 — macOS driver. Runs run.sh with a disposable HOME and TMPDIR
# under <scratch> and a minimal environment (env -i), then sweeps the whole
# real home for new files related to the tools under test.
#
#   sh macos.sh <scratch-dir> [test|lock|mise-lock]
#
# <scratch-dir> must be short (e.g. /tmp/h05): <scratch>/run is the <dest> of
# run.sh and <scratch>/tmp its TMPDIR, both limited to 60 characters.
# Environment: DITTO_SPIKE_WATCH_EXCLUDE / DITTO_SPIKE_REAL_HOME_EXCLUDE
# (extended regexes of unrelated noise), H05_* (passed through to run.sh).
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
[ $# -ge 1 ] || { echo "usage: $0 <scratch-dir> [test|lock|mise-lock]" >&2; exit 2; }
case "$1" in /*) ;; *) echo "scratch dir must be absolute" >&2; exit 2 ;; esac
mkdir -p "$1"
S=$(cd "$1" && pwd -P)
case "$S" in /|"$HOME"|"$HOME"/*) echo "refusing scratch dir $S (inside the real HOME or /)" >&2; exit 2 ;; esac
REAL_HOME=$HOME
# Only our own subdirectories are reset.
rm -rf "${S:?}/home" "${S:?}/tmp" "${S:?}/run"
mkdir -p "$S/home" "$S/tmp" "$S/run"
: >"$S/real-home-marker"
sleep 1

env -i HOME="$S/home" TMPDIR="$S/tmp" USER="${USER:-spike}" LANG="${LANG:-en_US.UTF-8}" \
	PATH=/usr/bin:/bin:/usr/sbin:/sbin DITTO_SPIKE_DISPOSABLE_HOME=1 \
	H05_CONTROL="${H05_CONTROL:-1}" H05_BASEDPYRIGHT="${H05_BASEDPYRIGHT:-1}" \
	H05_LSP_TIMEOUT="${H05_LSP_TIMEOUT:-120000}" \
	DITTO_SPIKE_WATCH_EXCLUDE="${DITTO_SPIKE_WATCH_EXCLUDE:-}" \
	sh "$HERE/run.sh" "$S/run" "${2:-test}"
rc=$?

find "$REAL_HOME" -newer "$S/real-home-marker" 2>/dev/null |
	awk -v s="$S/" 'index($0, s) != 1' |
	{ if [ -n "${DITTO_SPIKE_REAL_HOME_EXCLUDE:-}" ]; then grep -v -E "$DITTO_SPIKE_REAL_HOME_EXCLUDE"; else cat; fi; } \
		>"$S/real-home-new.txt" || true
found=$(grep -iE 'nvim|neovim|lazy|mason|mise|/\.npm|npm-cache|/go/pkg|go-build|/pip|pyright|vtsls|gopls|lua-language|tree-sitter|blink|node_modules|/\.cache/' \
	"$S/real-home-new.txt" || true)
if [ -n "$found" ]; then
	echo "RESULT T9-real-home FAIL $(echo "$found" | head -n 8 | tr '\n' ' ')"
	rc=1
else
	echo "RESULT T9-real-home PASS no nvim/mason/npm/pip/go/mise writes in the real \$HOME (whole-home sweep)"
fi
echo "RESULT T9-real-home-other INFO $(wc -l <"$S/real-home-new.txt" | tr -d ' ') unrelated new path(s) in the real \$HOME, listed in $S/real-home-new.txt"
exit "$rc"
