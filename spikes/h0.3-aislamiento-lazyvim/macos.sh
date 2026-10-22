#!/bin/sh
# Spike H0.3 — macOS driver. Runs run.sh with a disposable HOME and TMPDIR
# (the user fixtures and every tool write there, never in the real home) and
# a minimal environment, then sweeps the whole real home for new files.
#
#   sh macos.sh <scratch-dir> [test|lock]
#
# Environment: DITTO_SPIKE_WATCH_EXCLUDE / DITTO_SPIKE_REAL_HOME_EXCLUDE
# (extended regexes of unrelated noise), H03_SHELLS, H03_SCENARIOS,
# H03_GIT_MODES (passed through to run.sh).
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
[ $# -ge 1 ] || { echo "usage: $0 <scratch-dir> [test|lock]" >&2; exit 2; }
mkdir -p "$1"
S=$(cd "$1" && pwd -P)
REAL_HOME=$HOME
rm -rf "${S:?}/home" "${S:?}/tmp"
mkdir -p "$S/home" "$S/tmp" "$S/run"
: >"$S/real-home-marker"
sleep 1

env -i HOME="$S/home" TMPDIR="$S/tmp" USER="${USER:-$(id -un)}" LANG="${LANG:-en_US.UTF-8}" \
	PATH=/usr/bin:/bin:/usr/sbin:/sbin DITTO_SPIKE_DISPOSABLE_HOME=1 \
	H03_SHELLS="${H03_SHELLS:-zsh bash}" H03_SCENARIOS="${H03_SCENARIOS:-A B}" \
	H03_GIT_MODES="${H03_GIT_MODES:-none global include symlink}" \
	DITTO_SPIKE_WATCH_EXCLUDE="${DITTO_SPIKE_WATCH_EXCLUDE:-}" \
	sh "$HERE/run.sh" "$S/run" "${2:-test}"
rc=$?

find "$REAL_HOME" -newer "$S/real-home-marker" 2>/dev/null |
	awk -v s="$S/" 'index($0, s) != 1' |
	{ if [ -n "${DITTO_SPIKE_REAL_HOME_EXCLUDE:-}" ]; then grep -v -E "$DITTO_SPIKE_REAL_HOME_EXCLUDE"; else cat; fi; } \
		>"$S/real-home-new.txt" || true
found=$(grep -iE 'nvim|neovim|lazy|lazygit|mise|ripgrep|fzf|tree-sitter|\.zsh_history|\.bash_history|\.lesshst|\.gitconfig|/\.ssh/|/\.config/git' \
	"$S/real-home-new.txt" || true)
if [ -n "$found" ]; then
	echo "RESULT T6-real-home FAIL $(echo "$found" | head -n 8 | tr '\n' ' ')"
	rc=1
else
	echo "RESULT T6-real-home PASS no nvim/lazygit/mise/history/git/ssh writes in the real \$HOME (whole-home sweep)"
fi
echo "RESULT T6-real-home-other INFO $(wc -l <"$S/real-home-new.txt" | tr -d ' ') unrelated new path(s) in the real \$HOME, listed in $S/real-home-new.txt"
exit "$rc"
