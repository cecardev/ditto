#!/bin/sh
# Spike H0.4 — macOS driver. Runs run.sh with a disposable HOME and TMPDIR
# under a SHORT scratch dir (Neovim breaks with long paths, H0.3) and a
# minimal environment (env -i). Snapshots: the disposable HOME and TMPDIR,
# the workspace outside .ditto, /private/tmp, /private/var/tmp and the real
# per-user dirs DARWIN_USER_TEMP_DIR / DARWIN_USER_CACHE_DIR (where macOS
# APIs and `mktemp` without a template go when TMPDIR is ignored). Those and
# the real $HOME are only read (find), never written by this script.
#
#   sh macos.sh <scratch-dir>        e.g. /tmp/h04 (at most ~40 characters)
#
# Simulates Terminal.app (TERM_PROGRAM=Apple_Terminal + TERM_SESSION_ID) so
# /etc/zshrc_Apple_Terminal and its ~/.zsh_sessions logic run in the session.
# DITTO_SPIKE_REAL_HOME_EXCLUDE: extended regex of unrelated real-home noise.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
[ $# -ge 1 ] || { echo "usage: $0 <scratch-dir>" >&2; exit 2; }
mkdir -p "$1"
S=$(cd "$1" && pwd -P)
case "$S" in
/private/tmp/?*) ;;
*) echo "refusing: scratch dir must be under /tmp (short path); got $S" >&2; exit 2 ;;
esac
[ "${#S}" -le 40 ] || { echo "refusing: scratch dir longer than 40 characters" >&2; exit 2; }
REAL_HOME=$HOME
for _d in home tmp w run; do
	rm -rf "${S:?}/$_d"
done
mkdir -p "$S/home" "$S/tmp" "$S/w" "$S/run"
DTMP=$(getconf DARWIN_USER_TEMP_DIR)
DCACHE=$(getconf DARWIN_USER_CACHE_DIR)
DTMP=${DTMP%/}
DCACHE=${DCACHE%/}
: >"$S/real-home-marker"
sleep 1

env -i HOME="$S/home" TMPDIR="$S/tmp" USER="${USER:-$(id -un)}" LANG="${LANG:-en_US.UTF-8}" \
	PATH=/usr/bin:/bin:/usr/sbin:/sbin DITTO_SPIKE_DISPOSABLE_HOME=1 \
	H04_WS="$S/w" H04_SHELL=/bin/zsh H04_PHASES="${H04_PHASES:-A B}" H04_OC_RUN="${H04_OC_RUN:-1}" \
	H04_KEEP_WS="${H04_KEEP_WS:-0}" \
	H04_SNAP_ROOTS="home=$S/home tmpdir=$S/tmp ws=$S/w ptmp=/private/tmp vtmp=/private/var/tmp dtmp=$DTMP dcache=$DCACHE" \
	H04_SNAP_SHALLOW="ptmp vtmp dtmp dcache" \
	H04_SNAP_PRUNE="$S /private/tmp/claude-*" \
	H04_PTY_ENV_EXTRA="TERM_PROGRAM=Apple_Terminal TERM_SESSION_ID=h04-spike-session" \
	sh "$HERE/run.sh" "$S/run" full
rc=$?

# Real $HOME: read-only sweep for anything newer than the marker. Other git
# worktrees of this repo (concurrent agents) and the agent's own transcripts
# are always left out; DITTO_SPIKE_REAL_HOME_EXCLUDE adds more.
_excl='/\.claude/worktrees/|/\.claude/projects/'
[ -n "${DITTO_SPIKE_REAL_HOME_EXCLUDE:-}" ] && _excl="$_excl|$DITTO_SPIKE_REAL_HOME_EXCLUDE"
find "$REAL_HOME" -newer "$S/real-home-marker" 2>/dev/null | grep -v -E "$_excl" >"$S/real-home-new.txt" || true
# ~/.npm/_cacache is shared with every npm on the machine (other tools update
# it concurrently): only entries whose key names this spike's package count.
found=$(grep -iE 'nvim|neovim|lazy|lazygit|mise|mason|stylua|opencode|\.npm/_npx|\.npm/_logs|_update-notifier|\.bun|node_repl|\.zsh_history|\.zsh_sessions|\.bash_history|\.lesshst|\.gitconfig|/\.config/git|ripgrep|fzf|tree-sitter' \
	"$S/real-home-new.txt" || true)
ours=$(grep '/\.npm/_cacache/index-v5/' "$S/real-home-new.txt" | while read -r _f; do
	[ -f "$_f" ] && grep -l 'h04-fake-mcp' "$_f" 2>/dev/null
done)
[ -n "$ours" ] && found="$found $ours"
found=$(echo "$found" | sed 's/^ *//')
if [ -n "$found" ]; then
	echo "RESULT real-home FAIL $(echo "$found" | head -n 12 | tr '\n' ' ')"
	rc=1
else
	echo "RESULT real-home PASS no nvim/lazygit/mise/Mason/OpenCode/npm/history/git writes in the real \$HOME (whole-home sweep)"
fi
echo "RESULT real-home-other INFO $(wc -l <"$S/real-home-new.txt" | tr -d ' ') unrelated new path(s) in the real \$HOME, listed in $S/real-home-new.txt"
exit "$rc"
