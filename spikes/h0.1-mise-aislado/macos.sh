#!/bin/sh
# Spike H0.1 — macOS driver. Runs run.sh with a disposable HOME and TMPDIR
# (so even a leak cannot touch the real home), a fake host mise in it, and
# then scans the *real* home for mise-related files newer than the run.
#
#   sh macos.sh <scratch-dir>
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
[ $# -ge 1 ] || { echo "usage: $0 <scratch-dir>" >&2; exit 2; }
mkdir -p "$1"
S=$(cd "$1" && pwd -P)
REAL_HOME=$HOME
mkdir -p "$S/home" "$S/tmp" "$S/ws"
: >"$S/real-home-marker"
sleep 1

HOME="$S/home" TMPDIR="$S/tmp" DITTO_SPIKE_HOST_MISE=1 \
	DITTO_SPIKE_WATCH_EXCLUDE="${DITTO_SPIKE_WATCH_EXCLUDE:-^/tmp/claude-}" \
	sh "$HERE/run.sh" "$S/ws" all
rc=$?

# Real home: only the places where mise or its libraries could write.
found=$(for d in "$REAL_HOME/.config" "$REAL_HOME/.local" "$REAL_HOME/.cache" \
	"$REAL_HOME/Library/Caches" "$REAL_HOME/Library/Application Support" \
	"$REAL_HOME/Library/Preferences"; do
	[ -d "$d" ] && find "$d" -newer "$S/real-home-marker" 2>/dev/null
done | grep -iE 'mise|sigstore|aqua|nvim|neovim|opencode|lazygit|tree-sitter|ripgrep|fzf' || true)
if [ -n "$found" ]; then
	echo "RESULT T7-real-home FAIL $(echo "$found" | head -n 5 | tr '\n' ' ')"
	rc=1
else
	echo "RESULT T7-real-home PASS no mise-related writes in the real \$HOME"
fi
exit "$rc"
