#!/bin/sh
# shellcheck disable=SC2031 # ditto_mise sets HOME/TMPDIR only in its own subshell, on purpose
# shellcheck disable=SC2016 # single-quoted $ in generated scripts and probe commands, on purpose
# Spike H0.3 — LazyVim isolation with per-tool wrappers, .host-sh and a session
# shell without global XDG_*. Reproducible end to end:
#
#   sh run.sh <dest> [test|lock]
#
#   test (default)  install (mise of H0.1 + lock), wrappers, session rc,
#                   LazyVim starter + `Lazy! restore`, then cases 3-6 of the
#                   issue for every scenario x shell x git mode.
#   lock            regenerate starter/lazy-lock.json (Lazy! sync); prints the
#                   path of the new lock.
#
# <dest> is scratch space: <dest>/ws is the workspace (<dest>/ws/.ditto),
# <dest>/out the probe outputs, <dest>/logs the logs and results.txt.
#
# $HOME MUST be disposable: the script writes the user fixtures (~/.gitconfig,
# ~/.config/git, ~/.ssh/config, ~/.bashrc, ~/.zshrc...) there. It refuses to
# run unless DITTO_SPIKE_DISPOSABLE_HOME=1 (docker.sh/macos.sh set it).
#
# Environment:
#   H03_SHELLS="bash zsh"    shells to test (default: bash; zsh too if present)
#   H03_SCENARIOS="A B"      A: no XDG_*/ZDOTDIR on the host
#                            B: host exports XDG_CONFIG_HOME and ZDOTDIR
#   H03_GIT_MODES="none global include symlink"  see lib.sh
#
# Output: "RESULT <id> <PASS|FAIL|INFO> <detail>" lines (also in
# <dest>/logs/results.txt). Exit 1 if any FAIL.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
H03_DIR=$HERE
. "$HERE/lib.sh"

[ $# -ge 1 ] || { echo "usage: $0 <dest> [test|lock]" >&2; exit 2; }
[ "${DITTO_SPIKE_DISPOSABLE_HOME:-0}" = 1 ] || {
	echo "refusing: \$HOME must be disposable (set DITTO_SPIKE_DISPOSABLE_HOME=1; see macos.sh/docker.sh)" >&2
	exit 2
}
mkdir -p "$1"
DEST=$(cd "$1" && pwd -P)
MODE=${2:-test}
# Long paths break Neovim (see RESULTS.md, "Rutas largas"): vim.loader encodes
# the full path of every Lua file in one cache file name (NAME_MAX 255), and the
# RPC socket in $TMPDIR must fit in sun_path (104 bytes on macOS).
_tmpd=${TMPDIR:-/tmp}
if [ "${#DEST}" -gt 60 ] || [ "${#_tmpd}" -gt 60 ]; then
	echo "refusing: <dest> and \$TMPDIR must be at most 60 characters (got ${#DEST} / ${#_tmpd})" >&2
	exit 2
fi
WS="$DEST/ws"
OUT="$DEST/out"
LOGS="$DEST/logs"
REPO="$WS/repo"
mkdir -p "$WS" "$OUT" "$LOGS"
RESULTS="$LOGS/results.txt"
: >"$RESULTS"
FAILS=0

for _t in git ssh find awk sed sort cmp; do
	command -v "$_t" >/dev/null 2>&1 || { echo "run.sh needs '$_t' on PATH" >&2; exit 2; }
done

result() { # <id> <status> <detail...>
	_id=$1 _st=$2
	# XFAIL: expected failure of a git mode kept only as a control (none, global).
	[ "$_st" = FAIL ] && [ "${XFAIL:-0}" = 1 ] && _st=XFAIL
	shift 2
	echo "RESULT $_id $_st $*" | tee -a "$RESULTS"
	[ "$_st" = FAIL ] && FAILS=$((FAILS + 1))
	return 0
}

case "$(uname -s)" in
Darwin) BASE_PATH=/usr/bin:/bin:/usr/sbin:/sbin ;;
*) BASE_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ;;
esac
if [ -z "${H03_SHELLS:-}" ]; then
	H03_SHELLS=bash
	command -v zsh >/dev/null 2>&1 && H03_SHELLS="bash zsh"
fi
H03_SCENARIOS=${H03_SCENARIOS:-A B}
H03_GIT_MODES=${H03_GIT_MODES:-none global include symlink}

# ---------------------------------------------------------------------------
# Host fixtures (written to the disposable $HOME before the marker).
# ---------------------------------------------------------------------------

write_git_dir() { # <dir> <label>
	mkdir -p "$1"
	printf '[user]\n\temail = spike-%s@example.invalid\n[core]\n\tabbrev = 9\n[alias]\n\tspike%s = status\n' "$2" "$2" >"$1/config"
	printf '*.spikeignore\n' >"$1/ignore"
}

make_fixtures() {
	# Second guard on top of DITTO_SPIKE_DISPOSABLE_HOME: never overwrite a
	# user file. A freshly created HOME (macos.sh) or the image's /root with its
	# skeleton rc files removed (docker.sh) has none of these.
	for _f in .gitconfig .bashrc .zshrc .zshenv .ssh/config .config/git .xdg-config .zdot hostbin; do
		if [ -e "$HOME/$_f" ] || [ -L "$HOME/$_f" ]; then
			echo "refusing: \$HOME/$_f already exists; run.sh only writes its fixtures into an empty, disposable \$HOME" >&2
			exit 2
		fi
	done
	cat >"$HOME/.gitconfig" <<-'EOF'
		[user]
			name = Spike Gitconfig
		[alias]
			spikehome = log --oneline
		[init]
			defaultBranch = main
	EOF
	write_git_dir "$HOME/.config/git" xdgdefault
	write_git_dir "$HOME/.xdg-config/git" xdgcustom
	mkdir -p "$HOME/.ssh" "$HOME/hostbin" "$HOME/.zdot"
	chmod 0700 "$HOME/.ssh"
	cat >"$HOME/.ssh/config" <<-'EOF'
		Host spike-host
			HostName spike.example.invalid
			User spikeuser
			Port 2222
	EOF
	printf '#!/bin/sh\necho "fake host nvme"\n' >"$HOME/hostbin/nvme"
	chmod 0755 "$HOME/hostbin/nvme"
	# User rc files: they add a host dir in front of PATH (like conda/pyenv)
	# and, for zsh, a HISTFILE in $HOME that the session must override.
	cat >"$HOME/.bashrc" <<-'EOF'
		export PATH="$HOME/hostbin:$PATH"
		export DITTO_SPIKE_USER_RC=bash
	EOF
	cat >"$HOME/.zshrc" <<-'EOF'
		export PATH="$HOME/hostbin:$PATH"
		export DITTO_SPIKE_USER_RC=zsh-home
		HISTFILE="$HOME/.zsh_history"
		SAVEHIST=100
		HISTSIZE=100
	EOF
	sed 's/zsh-home/zsh-zdotdir/' "$HOME/.zshrc" >"$HOME/.zdot/.zshrc"
	printf 'export DITTO_SPIKE_USER_ZSHENV=zdotdir\n' >"$HOME/.zdot/.zshenv"
}

# ---------------------------------------------------------------------------
# Host environments: <name>.env (KEY=VALUE, for pty.lua) and <name>.sh
# (sourceable, for run_env). Only these variables reach the tests.
# ---------------------------------------------------------------------------

write_env() { # <scenario> <shell-path> <name>
	_f="$LOGS/$3"
	{
		echo "HOME=$HOME"
		echo "USER=${USER:-$(id -un)}"
		echo "LOGNAME=${USER:-$(id -un)}"
		echo "SHELL=$2"
		echo "TERM=xterm-256color"
		echo "LANG=${LANG:-C.UTF-8}"
		echo "PATH=$BASE_PATH"
		[ -n "${TMPDIR:-}" ] && echo "TMPDIR=$TMPDIR"
		[ "$(uname -s)" = Darwin ] && echo "BASH_SILENCE_DEPRECATION_WARNING=1"
		if [ "$1" = B ]; then
			echo "XDG_CONFIG_HOME=$HOME/.xdg-config"
			echo "ZDOTDIR=$HOME/.zdot"
		fi
	} >"$_f.env"
	sed "s/'/'\\\\''/g; s/^\([A-Za-z_][A-Za-z0-9_]*\)=\(.*\)$/export \1='\2'/" "$_f.env" >"$_f.sh"
}

run_env() { # <name> <cmd...> — runs cmd with exactly that host environment
	_f="$LOGS/$1.sh"
	shift
	env -i /bin/sh -c 'set -a; . "$1"; set +a; shift; exec "$@"' sh "$_f" "$@"
}

# ditto_run <cmd...> — how ditto itself (Go) would run a tool before the
# session (e.g. the headless `Lazy! restore` of §9): the user's environment
# (scenario A) plus .ditto/bin in front of PATH and DITTO_ROOT.
ditto_run() {
	run_env hostA env PATH="$DITTO_ROOT/bin:$BASE_PATH" DITTO_ROOT="$DITTO_ROOT" "$@"
}

# helper_nvim <args...> — the bare nvim binary for spike tooling (pty driver,
# extras merge), with its own throwaway HOME/XDG so it writes nothing that the
# $HOME sweep would count.
helper_nvim() {
	mkdir -p "$DEST/driver/tmp"
	HOME="$DEST/driver" XDG_CONFIG_HOME="$DEST/driver/config" XDG_DATA_HOME="$DEST/driver/data" \
		XDG_STATE_HOME="$DEST/driver/state" XDG_CACHE_HOME="$DEST/driver/cache" TMPDIR="$DEST/driver/tmp" \
		"$NVIM_BIN" --clean --headless -n -i NONE "$@"
}

# pty <env-name> <cwd> <steps-file> <transcript> <cmd...> — the child gets
# exactly <env-name>.env (clear_env), nothing of the driver.
pty() {
	_e="$LOGS/$1.env" _c=$2 _s=$3 _t=$4
	shift 4
	helper_nvim -l "$HERE/lua/pty.lua" "$_e" "$_c" "$_s" "$_t" "$@" 2>>"$LOGS/pty.log"
}

# ---------------------------------------------------------------------------
# Comparison helpers.
# ---------------------------------------------------------------------------

# cmp_ctx <id> <ctx-dir> <host-dir> <rt: absent|present> <env: same|skip> [user-git-dir]
cmp_ctx() {
	_id=$1 _d=$2 _h=$3
	if [ ! -f "$_d/done" ]; then
		result "$_id" FAIL "no probe output ($_d)"
		return
	fi
	_diff="" _equiv=""
	_files="git-origin git-values git-ignore ssh nvme"
	[ "$5" = same ] && _files="$_files env"
	for _x in $_files; do
		cmp -s "$_d/$_x.txt" "$_h/$_x.txt" && continue
		# Same files read through .ditto/config/git: the symlink (mode
		# "symlink") only changes the path printed by --show-origin/-v; the
		# include (mode "include") adds its own include.path entry.
		if [ -n "${6:-}" ] &&
			sed -e "\|include\.path=$6/config\$|d" -e "s|$DITTO_ROOT/config/git/|$6/|g" "$_d/$_x.txt" | cmp -s - "$_h/$_x.txt"; then
			_equiv="$_equiv $_x"
		else
			_diff="$_diff $_x"
		fi
	done
	_rt=present
	grep -q 'not found' "$_d/rt.txt" && _rt=absent
	[ "$_rt" = "$4" ] || _diff="$_diff runtime-path($_rt)"
	if [ -z "$_diff" ] && [ -n "$_equiv" ]; then
		result "$_id" PASS "equivalent to host: same values and files, but${_equiv} differ only by the .ditto/config/git path or its include.path line; runtime PATH $_rt"
	elif [ -z "$_diff" ]; then
		result "$_id" PASS "same as host (git config/origin/ignore, ssh -G, command -v nvme$([ "$5" = same ] && echo ', XDG_*/ZDOTDIR/GIT_CONFIG*/MISE_*')); runtime PATH $_rt"
	else
		result "$_id" FAIL "differs from host:$_diff"
		for _x in $_files; do
			cmp -s "$_d/$_x.txt" "$_h/$_x.txt" || diff "$_h/$_x.txt" "$_d/$_x.txt" >"$_d/$_x.diff"
		done
	fi
}

# ---------------------------------------------------------------------------
# Setup: tools, wrappers, session, starter.
# ---------------------------------------------------------------------------

setup() {
	h03_paths "$WS/.ditto" || exit 1
	h03_install_tools >"$LOGS/install.log" 2>&1 || { cat "$LOGS/install.log" >&2; exit 1; }
	NVIM_BIN=$(h03_tool nvim)
	h03_write_wrappers || exit 1
	h03_write_session || exit 1
	# Simulated mise runtime dir (nvim-only PATH, arch.md §8).
	mkdir -p "$DITTO_ROOT/spike/runtime/bin"
	printf '#!/bin/sh\necho ditto-runtime\n' >"$DITTO_ROOT/spike/runtime/bin/ditto-rt"
	chmod 0755 "$DITTO_ROOT/spike/runtime/bin/ditto-rt"
	# lazygit: ditto's config (in production, from the dotfiles repo).
	cat >"$DITTO_ROOT/config/lazygit/config.yml" <<-EOF
		update:
		  method: never
		disableStartupPopups: true
		git:
		  autoFetch: false
		customCommands:
		  - key: "<ctrl+x>"
		    context: global
		    command: "sh '$HERE/probe.sh' \$DITTO_SPIKE_TAG-lazygit '$OUT' '$REPO'"
		    output: none
	EOF
}

# install_starter <extras...> — starter + lazyvim.json merged with ditto's
# extras (repo's first, then ditto's).
install_starter() {
	h03_install_starter "$HERE/starter" >"$LOGS/starter.log" 2>&1 || { cat "$LOGS/starter.log" >&2; exit 1; }
	_j="$DITTO_ROOT/config/nvim/lazyvim.json"
	helper_nvim -l "$HERE/lua/merge-extras.lua" "$HERE/starter/lazyvim.json" "$_j" "$@" ||
		{ echo "merge-extras failed" >&2; exit 1; }
}

# Ditto's extras as the setup menu would pick them: one already in the repo
# (python), two new ones; prettier has a lower priority than the rest.
DITTO_EXTRAS="lazyvim.plugins.extras.lang.go lazyvim.plugins.extras.formatting.prettier lazyvim.plugins.extras.lang.python"

make_repo() {
	rm -rf "$REPO"
	mkdir -p "$REPO"
	run_env hostA git -C "$REPO" init -q
	echo "spike" >"$REPO/README.md"
	echo "ignored" >"$REPO/probe.spikeignore"
	run_env hostA git -C "$REPO" add README.md
	run_env hostA git -C "$REPO" -c user.email=spike@example.invalid commit -q -m init
}

# ---------------------------------------------------------------------------
# Lock mode.
# ---------------------------------------------------------------------------

if [ "$MODE" = lock ]; then
	make_fixtures
	write_env A /bin/sh hostA
	setup
	rm -f "$HERE/starter/lazy-lock.json.new"
	_tmp="$DEST/starter-nolock"
	rm -rf "$_tmp"
	cp -R "$HERE/starter" "$_tmp"
	rm -f "$_tmp/lazy-lock.json"
	H03_ALLOW_UNPINNED_LAZY=1 h03_install_starter "$_tmp" >"$LOGS/starter.log" 2>&1 || { cat "$LOGS/starter.log" >&2; exit 1; }
	# shellcheck disable=SC2086 # word splitting of the extras list is intended
	helper_nvim -l "$HERE/lua/merge-extras.lua" "$HERE/starter/lazyvim.json" \
		"$DITTO_ROOT/config/nvim/lazyvim.json" $DITTO_EXTRAS
	ditto_run nvim --headless "+Lazy! sync" +qa >"$LOGS/lazy-sync.log" 2>&1
	cp "$DITTO_ROOT/config/nvim/lazy-lock.json" "$DEST/lazy-lock.json"
	echo "$DEST/lazy-lock.json"
	exit 0
fi

# ---------------------------------------------------------------------------
# Test mode.
# ---------------------------------------------------------------------------

make_fixtures
for _sc in $H03_SCENARIOS; do
	for _sh in $H03_SHELLS; do
		write_env "$_sc" "$(command -v "$_sh")" "host$_sc-$_sh"
	done
done
write_env A /bin/sh hostA
setup
make_repo
# lazygit 0.66 exits at startup with "Git version must be at least 2.32"
# (Ubuntu 18.04 ships 2.17, 20.04 ships 2.25): its case is skipped there.
GIT_VERSION=$(git --version | sed -n 's/^git version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
LAZYGIT_OK=0
[ "$(printf '2.32\n%s\n' "$GIT_VERSION" | sort -t. -k1,1n -k2,2n | head -n 1)" = 2.32 ] && LAZYGIT_OK=1

# Host baselines: the user's plain interactive shell (user rc loaded), before
# the marker: whatever the host shell writes (e.g. ~/.zsh_history) is the
# host's own behaviour, not ditto's.
for _sc in $H03_SCENARIOS; do
	for _sh in $H03_SHELLS; do
		_st="$LOGS/steps-host-$_sc-$_sh"
		{
			echo "send sh '$HERE/probe.sh' host-$_sc-$_sh '$OUT' '$REPO'"
			echo "wait $OUT/host-$_sc-$_sh/done 20000"
			echo "send echo host-history-marker"
			echo "send exit"
			echo "exit 10000"
		} >"$_st"
		rm -rf "$OUT/host-$_sc-$_sh"
		pty "host$_sc-$_sh" "$REPO" "$_st" "$LOGS/pty-host-$_sc-$_sh.txt" "$(command -v "$_sh")" -i ||
			result "T4-$_sc-$_sh-host" FAIL "host baseline did not complete"
	done
done
_ctl=""
for _f in "$HOME/.zsh_history" "$HOME/.zdot/.zsh_history" "$HOME/.bash_history"; do
	grep -q host-history-marker "$_f" 2>/dev/null && _ctl="$_ctl ${_f#"$HOME"/}"
done
result T6-control INFO "host shells without ditto write history to:${_ctl:- (none)} (expected for zsh with HISTFILE in the user rc, and for bash)"

MARKER="$LOGS/marker"
: >"$MARKER"
sleep 1
# shellcheck disable=SC2086
install_starter $DITTO_EXTRAS
result T0-tools INFO "nvim $(helper_nvim --version 2>/dev/null | head -n 1 | cut -d' ' -f2) ($NVIM_BIN); git $(git --version | cut -d' ' -f3); $(ssh -V 2>&1 | cut -d, -f1)"

# --- Case 2: Lazy! restore (as ditto would run it: user env + wrapper). ---
H03_GIT_MODE=symlink h03_write_nvim_wrapper "$NVIM_BIN"
if ditto_run nvim --headless "+Lazy! restore" +qa >"$LOGS/lazy-restore.log" 2>&1; then
	_n=0 _bad=""
	for _p in "$DITTO_ROOT"/data/nvim/lazy/*/; do
		_name=$(basename "$_p")
		_want=$(sed -n "s/.*\"$_name\": *{ *\"branch\": *\"[^\"]*\", *\"commit\": *\"\([0-9a-f]*\)\".*/\1/p" "$DITTO_ROOT/config/nvim/lazy-lock.json")
		[ -n "$_want" ] || continue
		_n=$((_n + 1))
		_have=$(git -C "$_p" rev-parse HEAD 2>/dev/null)
		[ "$_have" = "$_want" ] || _bad="$_bad $_name"
	done
	if [ -z "$_bad" ] && [ "$_n" -gt 0 ]; then
		result T2-lazy-restore PASS "$_n plugins at the commits of lazy-lock.json"
	else
		result T2-lazy-restore FAIL "plugins not at lock commit:$_bad (checked $_n)"
	fi
else
	result T2-lazy-restore FAIL "nvim exited non-zero (see $LOGS/lazy-restore.log)"
fi
if [ -L "$DITTO_ROOT/config/nvim" ] || cmp -s "$HERE/starter/lazy-lock.json" "$DITTO_ROOT/config/nvim/lazy-lock.json"; then
	result T2-lock-unchanged PASS "Lazy! restore left lazy-lock.json unchanged"
else
	result T2-lock-unchanged FAIL "lazy-lock.json changed"
fi
grep -iE 'error|warn' "$LOGS/lazy-restore.log" >/dev/null 2>&1 &&
	result T2-restore-log INFO "errors/warnings in lazy-restore.log: $(grep -icE 'error|warn' "$LOGS/lazy-restore.log")"

# --- Case 5: extras merge and import order. ---
_j="$DITTO_ROOT/config/nvim/lazyvim.json"
result T5-merged INFO "lazyvim.json extras: $(tr -d '\n ' <"$_j" | sed 's/.*"extras":\[\([^]]*\)\].*/\1/')"
ditto_run env DITTO_SPIKE_ORDER_OUT="$OUT/order-1.json" nvim --headless \
	"+lua dofile('$HERE/lua/extras-order.lua')" >"$LOGS/order-1.log" 2>&1
# Same extras, reversed order on both sides: LazyVim must import them identically.
_rev=""
for _e in $DITTO_EXTRAS; do _rev="$_e $_rev"; done
printf '{"extras":["lazyvim.plugins.extras.coding.mini-surround","lazyvim.plugins.extras.lang.python"],"install_version":8,"news":{},"version":8}\n' >"$DEST/lazyvim-rev.json"
cp "$_j" "$DEST/lazyvim-merged.json"
# shellcheck disable=SC2086
helper_nvim -l "$HERE/lua/merge-extras.lua" "$DEST/lazyvim-rev.json" "$_j" $_rev
ditto_run env DITTO_SPIKE_ORDER_OUT="$OUT/order-2.json" nvim --headless \
	"+lua dofile('$HERE/lua/extras-order.lua')" >"$LOGS/order-2.log" 2>&1
cp "$DEST/lazyvim-merged.json" "$_j"
_m1=$(sed -n 's/.*"modules":\[\([^]]*\)\].*/\1/p' "$OUT/order-1.json")
_m2=$(sed -n 's/.*"modules":\[\([^]]*\)\].*/\1/p' "$OUT/order-2.json")
if [ -n "$_m1" ] && [ "$_m1" = "$_m2" ]; then
	result T5-order PASS "same import order with the lists reversed: $(echo "$_m1" | tr -d '"' | sed 's/lazyvim\.plugins\.extras\.//g')"
else
	result T5-order FAIL "import order differs: [$_m1] vs [$_m2]"
fi
for _e in $DITTO_EXTRAS lazyvim.plugins.extras.coding.mini-surround; do
	echo "$_m1" | grep -q "\"$_e\"" || result T5-loaded FAIL "$_e not imported"
done
if grep -q '"msg":"[^"]*order of your' "$OUT/order-1.json" || grep -qi 'order of your' "$LOGS/order-1.log"; then
	result T5-warnings FAIL "LazyVim import-order warning"
else
	_w=$(sed -n 's/.*"notify_calls":\(\[[^]]*\]\).*/\1/p' "$OUT/order-1.json")
	result T5-warnings PASS "no import-order warning; vim.notify calls: ${_w:-[]}"
fi
# Control: importing an extra by hand after { import = "plugins" } must
# produce LazyVim's warning, so its absence above means something.
_ll="$DITTO_ROOT/config/nvim/lua/config/lazy.lua"
cp "$_ll" "$DEST/lazy.lua.orig"
sed 's|    { import = "plugins" },|    { import = "plugins" },\
    { import = "lazyvim.plugins.extras.lang.toml" },|' "$DEST/lazy.lua.orig" >"$_ll"
ditto_run env DITTO_SPIKE_ORDER_OUT="$OUT/order-bad.json" nvim --headless \
	"+lua dofile('$HERE/lua/extras-order.lua')" >"$LOGS/order-bad.log" 2>&1
cp "$DEST/lazy.lua.orig" "$_ll"
if grep -q 'order of your' "$OUT/order-bad.json" "$LOGS/order-bad.log" 2>/dev/null; then
	result T5-warnings-control PASS "an extra imported after 'plugins' does trigger the import-order warning (detection works)"
else
	result T5-warnings-control FAIL "wrong import order produced no detectable warning"
fi

# --- Cases 3, 4 and 6 for every scenario x shell x git mode. ---
for _sc in $H03_SCENARIOS; do
	for _sh in $H03_SHELLS; do
		_env="host$_sc-$_sh"
		# The git dir the host itself reads ($XDG_CONFIG_HOME/git or ~/.config/git).
		_ugit="$HOME/.config/git"
		[ "$_sc" = B ] && _ugit="$HOME/.xdg-config/git"
		for _mode in $H03_GIT_MODES; do
			_tag="$_sc-$_sh-$_mode"
			H03_GIT_MODE=$_mode h03_write_nvim_wrapper "$NVIM_BIN"
			rm -rf "$DITTO_ROOT/config/git" "$OUT/$_tag"-* "$OUT/$_tag-nvim.json"
			rm -f "$DITTO_ROOT/state/shell/${_sh}_history"
			_st="$LOGS/steps-$_tag"
			{
				echo "send env | LC_ALL=C sort > '$OUT/$_tag-session.env'"
				echo "send sh '$HERE/probe.sh' $_tag-session '$OUT' '$REPO'"
				echo "wait $OUT/$_tag-session/done 20000"
				echo "send DITTO_SPIKE_PROBE='$HERE/probe.sh' DITTO_SPIKE_OUT='$OUT' DITTO_SPIKE_REPO='$REPO' DITTO_SPIKE_TAG=$_tag nvim --headless \"+lua dofile('$HERE/lua/probe.lua')\""
				echo "wait $OUT/$_tag-nvim.json 180000"
				echo "send echo ditto-history-marker-$_tag"
				echo "send exit"
				echo "exit 20000"
			} >"$_st"
			pty "$_env" "$REPO" "$_st" "$LOGS/pty-$_tag.txt" "$DITTO_ROOT/shell/session" ||
				result "T4-$_tag-run" FAIL "session run did not complete (see $LOGS/pty-$_tag.txt)"
			_h="$OUT/host-$_sc-$_sh"

			# Case 3: session environment.
			_se="$OUT/$_tag-session.env"
			_hx=$(grep -E '^XDG_' "$LOGS/$_env.env" | LC_ALL=C sort | tr '\n' ' ')
			_sx=$(grep -E '^XDG_' "$_se" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
			_bad=""
			[ "$_hx" = "$_sx" ] || _bad="$_bad XDG[$_sx]"
			grep -q '^MISE_' "$_se" 2>/dev/null && _bad="$_bad MISE_*"
			_p=$(sed -n 's/^PATH=//p' "$_se")
			case "$_p" in "$DITTO_ROOT/bin:$HOME/hostbin:"*) ;; *) _bad="$_bad PATH-order[$(echo "$_p" | cut -d: -f1-2)]" ;; esac
			if [ "$_sh" = zsh ]; then
				_hz=$(grep '^ZDOTDIR=' "$LOGS/$_env.env")
				_sz=$(grep '^ZDOTDIR=' "$_se")
				[ "$_hz" = "$_sz" ] || _bad="$_bad ZDOTDIR[$_sz]"
				grep -q '^DITTO_ORIG_ZDOTDIR=' "$_se" && _bad="$_bad DITTO_ORIG_ZDOTDIR-left"
			fi
			grep -q '^DITTO_SPIKE_USER_RC=' "$_se" || _bad="$_bad user-rc-not-loaded"
			if [ -z "$_bad" ]; then
				result "T3-$_tag-session-env" PASS "XDG_* as host ($([ -n "$_hx" ] && echo "$_hx" || echo none)), no MISE_*, user rc loaded, PATH .ditto/bin then user rc dirs$([ "$_sh" = zsh ] && echo ", ZDOTDIR restored ($(echo "$_hz" | sed 's/^ZDOTDIR=//; s/^$/unset/'))")"
			else
				result "T3-$_tag-session-env" FAIL "$_bad"
			fi

			# Case 4: each context vs the host baseline.
			cmp_ctx "T4-$_tag-session" "$OUT/$_tag-session" "$_h" absent same
			for _c in terminal bang system snacks; do
				cmp_ctx "T4-$_tag-$_c" "$OUT/$_tag-$_c" "$_h" absent same
			done
			if [ "$LAZYGIT_OK" = 1 ]; then
				cmp_ctx "T4-$_tag-lazygit" "$OUT/$_tag-lazygit" "$_h" absent same
			else
				result "T4-$_tag-lazygit" SKIP "lazygit $DITTO_V_LAZYGIT refuses to start with git $GIT_VERSION (needs >= 2.32)"
			fi
			for _c in list gitsigns; do
				XFAIL=0
				[ "$_mode" = symlink ] || XFAIL=1
				cmp_ctx "T4-$_tag-$_c" "$OUT/$_tag-$_c" "$_h" present skip "$_ugit"
				XFAIL=0
			done
			if [ -f "$OUT/$_tag-nvim.json" ]; then
				if grep -q '"attached":true' "$OUT/$_tag-nvim.json"; then
					result "T4-$_tag-gitsigns-attach" PASS "gitsigns attached to the repo"
				else
					result "T4-$_tag-gitsigns-attach" FAIL "gitsigns did not attach"
				fi
			fi

			# Case 6: history inside .ditto, not in $HOME.
			_hf="$DITTO_ROOT/state/shell/${_sh}_history"
			if grep -q "ditto-history-marker-$_tag" "$_hf" 2>/dev/null; then
				result "T6-$_tag-history" PASS "history written to .ditto/state/shell/${_sh}_history"
			else
				result "T6-$_tag-history" FAIL "marker not in $_hf"
			fi
		done
	done
done

# --- .host-sh -c <cmd> [args]: the form OpenCode's `shell` key would use (#2). ---
_o=$(run_env hostA env DITTO_NVIM=1 DITTO_ORIG_PATH="$BASE_PATH" PATH="/nonexistent:$BASE_PATH" \
	XDG_CONFIG_HOME="$DITTO_ROOT/config" "$DITTO_ROOT/bin/.host-sh" -c \
	'printf "%s|%s|%s|%s|%s\n" "${XDG_CONFIG_HOME-unset}" "${DITTO_NVIM-unset}" "$PATH" "$0" "$1"' arg0 arg1 2>&1)
if [ "$_o" = "unset|unset|$BASE_PATH|arg0|arg1" ]; then
	result T7-host-sh-c PASS ".host-sh -c '<cmd>' arg0 arg1: environment restored, \$0/\$1 passed through"
else
	result T7-host-sh-c FAIL "got: $_o"
fi

# --- Case 6 (global): nothing new in $HOME (FAIL) or the temp dir (INFO). ---
_tmpw=${TMPDIR:-/tmp}
for _w in home tmp; do
	_root=$HOME
	[ "$_w" = tmp ] && _root=$_tmpw
	find "$_root" -newer "$MARKER" 2>/dev/null |
		awk -v dest="$DEST/" -v root="$_root" 'index($0, dest) == 1 { next } $0 == root || $0 == root "/" { next } { print }' |
		{ if [ -n "${DITTO_SPIKE_WATCH_EXCLUDE:-}" ]; then grep -v -E "$DITTO_SPIKE_WATCH_EXCLUDE"; else cat; fi; } \
			>"$LOGS/new-$_w.txt" || true
done
if [ -s "$LOGS/new-home.txt" ]; then
	result T6-outside-home FAIL "$(wc -l <"$LOGS/new-home.txt" | tr -d ' ') path(s) written in \$HOME: $(head -n 8 "$LOGS/new-home.txt" | tr '\n' ' ')"
else
	result T6-outside-home PASS "nothing new in \$HOME ($HOME) after all sessions (history, lazygit state, nvim state included)"
fi
if [ -s "$LOGS/new-tmp.txt" ]; then
	result T6-outside-tmp INFO "temp dir ($_tmpw): $(sed "s|^$_tmpw/||" "$LOGS/new-tmp.txt" | awk -F/ '{print $1}' | sort -u | tr '\n' ' ')(sockets/temp files, for #6)"
else
	result T6-outside-tmp PASS "nothing new in $_tmpw"
fi

echo "== $(grep -c ' PASS ' "$RESULTS") PASS, $FAILS FAIL, $(grep -c ' XFAIL ' "$RESULTS") XFAIL (control git modes), $(grep -c ' INFO ' "$RESULTS") INFO" | tee -a "$RESULTS"
[ "$FAILS" -eq 0 ]
