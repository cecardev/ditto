#!/bin/sh
# Spike H0.1 — macOS driver. Runs run.sh with a disposable HOME and TMPDIR
# (so even a leak cannot touch the real home), a fake host mise in it, and
# then sweeps the *whole* real home for files newer than the run.
#
#   sh macos.sh <scratch-dir>
#
# Environment:
#   DITTO_SPIKE_WATCH_EXCLUDE=<re>      passed to run.sh (noise in /tmp from
#                                       unrelated processes); no default
#   DITTO_SPIKE_REAL_HOME_EXCLUDE=<re>  extra paths of the real home to ignore
#                                       (apps writing concurrently); no default
#
# Real-home sweep: `find "$HOME" -newer <marker>`. Any path that looks like
# mise or one of the tools (mise, sigstore, aqua, conda, nvim, opencode…)
# is a FAIL. Every other new path is unrelated activity of the machine
# (browsers, IDEs, this very agent…): it is listed in
# <scratch>/real-home-new.txt and reported as INFO for manual review.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
[ $# -ge 1 ] || { echo "usage: $0 <scratch-dir>" >&2; exit 2; }
mkdir -p "$1"
S=$(cd "$1" && pwd -P)
REAL_HOME=$HOME
mkdir -p "$S/home" "$S/tmp" "$S/ws"
: >"$S/real-home-marker"
sleep 1

HOME="$S/home" TMPDIR="$S/tmp" DITTO_SPIKE_HOST_MISE=1 DITTO_SPIKE_DISPOSABLE_HOME=1 \
	sh "$HERE/run.sh" "$S/ws" all
rc=$?

# Whole real home. Excluded: the scratch dir itself if it lives under HOME,
# and whatever the caller adds. Unreadable (TCC-protected) dirs are skipped.
find "$REAL_HOME" -newer "$S/real-home-marker" 2>/dev/null |
	awk -v s="$S/" 'index($0, s) != 1' |
	{ if [ -n "${DITTO_SPIKE_REAL_HOME_EXCLUDE:-}" ]; then grep -v -E "$DITTO_SPIKE_REAL_HOME_EXCLUDE"; else cat; fi; } \
		>"$S/real-home-new.txt" || true
found=$(grep -iE 'mise|sigstore|aqua|conda|nvim|neovim|opencode|lazygit|tree-sitter|ripgrep|fzf' \
	"$S/real-home-new.txt" || true)
if [ -n "$found" ]; then
	echo "RESULT T7-real-home FAIL $(echo "$found" | head -n 5 | tr '\n' ' ')"
	rc=1
else
	echo "RESULT T7-real-home PASS no mise-related writes in the real \$HOME (whole-home sweep)"
fi
echo "RESULT T7-real-home-other INFO $(wc -l <"$S/real-home-new.txt" | tr -d ' ') unrelated new path(s) in the real \$HOME, listed in $S/real-home-new.txt"
exit "$rc"
