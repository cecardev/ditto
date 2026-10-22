#!/bin/sh
# Spike H0.3 — what the user would observe in a given context. Run on the
# host, in the session and from every Neovim child; run.sh compares outputs.
#
#   sh probe.sh <context> <out-dir> <repo>
#
# Writes <out-dir>/<context>/{git-origin,git-values,git-ignore,ssh,nvme,rt,env}.txt
# and then <out-dir>/<context>/done.
set -u
ctx=$1
out=$2/$ctx
repo=$3
mkdir -p "$out"
cd "$repo" || exit 1

git config --show-origin --list >"$out/git-origin.txt" 2>&1
git config --list >"$out/git-values.txt" 2>&1
# Default global ignore file: $XDG_CONFIG_HOME/git/ignore or ~/.config/git/ignore.
git check-ignore -v probe.spikeignore >"$out/git-ignore.txt" 2>&1
# ssh resolves ~ with getpwuid(), not $HOME: on macOS (disposable HOME) point
# it at the test config explicitly so the user's real ~/.ssh is never read.
# stderr apart: without a TTY on stdin ssh adds "Pseudo-terminal will not be
# allocated", which is not a configuration difference.
if [ "$(uname -s)" = Darwin ]; then
	ssh -F "$HOME/.ssh/config" -G spike-host >"$out/ssh.txt" 2>"$out/ssh.err"
else
	ssh -G spike-host >"$out/ssh.txt" 2>"$out/ssh.err"
fi
command -v nvme >"$out/nvme.txt" 2>&1 || echo "nvme: not found" >"$out/nvme.txt"
# Marker of the nvim-only runtime PATH (mise runtimes for Mason).
command -v ditto-rt >"$out/rt.txt" 2>&1 || echo "ditto-rt: not found" >"$out/rt.txt"
# Variables that must be exactly the host's in every shell context.
env | grep -E '^(XDG_|DITTO_ORIG_|DITTO_NVIM=|GIT_CONFIG|ZDOTDIR=|MISE_)' | LC_ALL=C sort >"$out/env.txt"
# Variables ditto sets on purpose (history, lazygit), for the record.
env | grep -E '^(HISTFILE|LESSHISTFILE|NODE_REPL_HISTORY|PYTHON_HISTORY|LG_CONFIG_FILE|CONFIG_DIR|DITTO_ROOT|DITTO_ACTIVE)=' |
	LC_ALL=C sort >"$out/env-ditto.txt"
printf '%s\n' "$PATH" >"$out/path.txt"
: >"$out/done"
