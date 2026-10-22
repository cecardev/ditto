#!/bin/sh
# Spike H0.1b — macOS driver. Runs run.sh with a disposable HOME and TMPDIR
# and a clean environment (env -i), then sweeps the whole real home for
# files newer than the run, like spikes/h0.1-mise-aislado/macos.sh.
#
#   sh macos.sh <scratch-dir>
#
# Environment:
#   DITTO_SPIKE_WATCH_EXCLUDE=<re>      passed to run.sh; no default
#   DITTO_SPIKE_REAL_HOME_EXCLUDE=<re>  extra real-home paths to ignore; no default
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
[ $# -ge 1 ] || { echo "usage: $0 <scratch-dir>" >&2; exit 2; }
mkdir -p "$1"
S=$(cd "$1" && pwd -P)
REAL_HOME=$HOME

mkdir -p "$S/home" "$S/tmp"
: >"$S/real-home-marker"
sleep 1

env -i HOME="$S/home" TMPDIR="$S/tmp" PATH=/usr/bin:/bin:/usr/sbin:/sbin TERM=dumb LANG=C DITTO_SPIKE_DISPOSABLE_HOME=1 \
	DITTO_SPIKE_WATCH_EXCLUDE="${DITTO_SPIKE_WATCH_EXCLUDE:-}" \
	sh "$HERE/run.sh" "$S/dest"
rc=$?

find "$REAL_HOME" -newer "$S/real-home-marker" 2>/dev/null |
	awk -v s="$S/" -v repo="$(cd "$HERE/../.." && pwd -P)" 'index($0, s) != 1 && index($0, repo) != 1' |
	{ if [ -n "${DITTO_SPIKE_REAL_HOME_EXCLUDE:-}" ]; then grep -v -E "$DITTO_SPIKE_REAL_HOME_EXCLUDE"; else cat; fi; } \
		>"$S/real-home-new.txt" || true
found=$(grep -iE 'mise|sigstore|aqua|conda|nvim|neovim|lazygit|ripgrep|zsh_history|bash_history|zcompdump' \
	"$S/real-home-new.txt" || true)
if [ -n "$found" ]; then
	echo "RESULT T7-real-home FAIL $(echo "$found" | head -n 5 | tr '\n' ' ')"
	rc=1
else
	echo "RESULT T7-real-home PASS no mise/shell/tool writes in the real \$HOME (whole-home sweep)"
fi
echo "RESULT T7-real-home-other INFO $(wc -l <"$S/real-home-new.txt" | tr -d ' ') unrelated new path(s), listed in $S/real-home-new.txt"
exit "$rc"
