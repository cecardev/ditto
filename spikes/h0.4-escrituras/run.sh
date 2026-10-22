#!/bin/sh
# shellcheck disable=SC2016 # single-quoted $ in typed commands, on purpose
# shellcheck disable=SC2031 # ditto_mise sets HOME/TMPDIR only in its own subshell, on purpose
# shellcheck disable=SC2028 # "key \3" is a literal step for pty.lua, not an escape
# Spike H0.4 — what a real LazyVim + OpenCode session writes outside .ditto/.
# Snapshot -> session -> diff, end to end:
#
#   sh run.sh <dest> [full|opencode]
#
#   S0  snapshot (user fixtures and project repo already in place)
#   --  install: mise + tools (H0.1 lock), Node.js, wrappers, session rc,
#       LazyVim starter (H0.3) with Mason enabled
#   S1  snapshot
#   A   session with the wrappers as H0.2/H0.3 left them ("current"): see
#       steps_session below (Lazy! restore, Mason install, nvim TUI session,
#       OpenCode, lazygit, nested shell, exit)
#   S2  snapshot
#   B   same session with the proposed mechanisms (h04_apply_proposed)
#   S3  snapshot
#   --  delete the workspace (.ditto and the project)
#   S4  snapshot: S0 -> S4 must only show what is accepted (RESULTS.md)
#
#   opencode profile: same install without the starter; the session only runs
#   the OpenCode steps (Ubuntu 22.04 amd64: the /tmp mtime question of H0.2).
#
# $HOME MUST be disposable (fixtures are written there): DITTO_SPIKE_DISPOSABLE_HOME=1
# (macos.sh / docker.sh). Environment:
#   H04_WS            workspace dir (default <dest>/w); its .ditto is pruned
#   H04_SNAP_ROOTS    "label=path ..." roots to snapshot (default: "root=/")
#   H04_SNAP_PRUNE    extra paths/globs to leave out of every snapshot
#   H04_SNAP_SHALLOW  labels snapshotted with maxdepth 3 (big shared dirs)
#   H04_PTY_ENV_EXTRA extra KEY=VALUE lines for the session environment
#   H04_STRACE=1      run the sessions under strace -f -e trace=file (Linux)
#   H04_INOTIFY="dir ..."  inotifywait on these dirs during the sessions
#   H04_PHASES        default "A B"; "B" alone = only the proposed mechanisms,
#                     so S0 -> S9 shows what remains with them
#   H04_OC_RUN=1      opt-in: send one short `opencode run` to OpenCode Zen (free model)
#   H04_KEEP_WS=1     keep the workspace at the end (manual checks), no S9
#
# Output: "RESULT <id> <PASS|FAIL|INFO> ..." lines (<dest>/logs/results.txt),
# diffs in <dest>/logs/diff-*.txt.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
H04_DIR=$HERE
. "$HERE/lib.sh"

[ $# -ge 1 ] || { echo "usage: $0 <dest> [full|opencode]" >&2; exit 2; }
[ "${DITTO_SPIKE_DISPOSABLE_HOME:-0}" = 1 ] || {
	echo "refusing: \$HOME must be disposable (DITTO_SPIKE_DISPOSABLE_HOME=1; see macos.sh/docker.sh)" >&2
	exit 2
}
# Second guard: HOME is not the account's real home. In a container (the
# image's user is disposable) anything goes; on a host it must be a fresh
# directory under /tmp.
_real_home=""
if command -v getent >/dev/null 2>&1; then
	_real_home=$(getent passwd "$(id -un)" | cut -d: -f6)
elif command -v dscl >/dev/null 2>&1; then
	_real_home=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
fi
if [ ! -f /.dockerenv ]; then
	case "$HOME" in
	/tmp/?* | /private/tmp/?*) ;;
	*) echo "refusing: \$HOME ($HOME) must be under /tmp or /private/tmp outside a container" >&2; exit 2 ;;
	esac
	if [ -z "$_real_home" ] || [ "$HOME" = "$_real_home" ]; then
		echo "refusing: \$HOME is the account's real home (or it cannot be determined)" >&2
		exit 2
	fi
fi
# Resolve <dest> and validate the workspace before writing anything: it is
# deleted at the end, so it may only be <dest>/w, the Docker /w or the sibling
# <scratch>/w of macos.sh.
_dparent=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || { echo "parent of <dest> must exist" >&2; exit 2; }
DEST="$_dparent/$(basename "$1")"
PROFILE=${2:-full}
WS=${H04_WS:-$DEST/w}
case "$WS" in
"$DEST"/w | /w | "${DEST%/*}/w") ;;
*) echo "refusing: unexpected workspace path $WS (allowed: <dest>/w, /w, <dest>/../w)" >&2; exit 2 ;;
esac
mkdir -p "$DEST" "$WS"
DEST=$(cd "$DEST" && pwd -P)
WS=$(cd "$WS" && pwd -P)
_tmpd=${TMPDIR:-/tmp}
# Long paths break Neovim (H0.3, "Rutas largas").
if [ "${#WS}" -gt 60 ] || [ "${#_tmpd}" -gt 60 ] || [ "${#DEST}" -gt 60 ]; then
	echo "refusing: <dest>, workspace and \$TMPDIR must be at most 60 characters" >&2
	exit 2
fi
LOGS="$DEST/logs"
OUT="$DEST/out"
SNAP="$DEST/snap"
DL="$DEST/dl"
PROJ="$WS/proj"
mkdir -p "$LOGS" "$OUT" "$SNAP" "$DL"
RESULTS="$LOGS/results.txt"
: >"$RESULTS"
FAILS=0
H04_PHASES=${H04_PHASES:-A B}
H04_SNAP_ROOTS=${H04_SNAP_ROOTS:-root=/}

result() { # <id> <status> <detail...>
	_id=$1 _st=$2
	shift 2
	echo "RESULT $_id $_st $*" | tee -a "$RESULTS"
	[ "$_st" = FAIL ] && FAILS=$((FAILS + 1))
	return 0
}

case "$(uname -s)" in
Darwin) BASE_PATH=/usr/bin:/bin:/usr/sbin:/sbin ;;
*) BASE_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin ;;
esac
SESSION_SHELL=${H04_SHELL:-$(command -v bash)}

# ---------------------------------------------------------------------------
# Fixtures: the user's own files (disposable HOME) and project.
# ---------------------------------------------------------------------------

make_fixtures() {
	for _f in .gitconfig .bashrc .zshrc .config/git; do
		if [ -e "$HOME/$_f" ] || [ -L "$HOME/$_f" ]; then
			echo "refusing: \$HOME/$_f already exists; run.sh only writes into an empty, disposable \$HOME" >&2
			exit 2
		fi
	done
	printf '[user]\n\tname = Spike User\n\temail = spike@example.invalid\n[init]\n\tdefaultBranch = main\n' >"$HOME/.gitconfig"
	mkdir -p "$HOME/.config/git"
	printf '[alias]\n\tst = status\n' >"$HOME/.config/git/config"
	printf '*.spikeignore\n' >"$HOME/.config/git/ignore"
	# User rc files as they typically are: zsh with its history in $HOME.
	printf 'export H04_USER_RC=bash\n' >"$HOME/.bashrc"
	printf 'export H04_USER_RC=zsh\nHISTFILE="$HOME/.zsh_history"\nSAVEHIST=100\nHISTSIZE=100\n' >"$HOME/.zshrc"
	# The project the user works on, inside the workspace (outside .ditto).
	mkdir -p "$PROJ"
	printf 'spike\n' >"$PROJ/README.md"
	cat >"$PROJ/opencode.json" <<-EOF
		{
		  "\$schema": "https://opencode.ai/config.json",
		  "autoupdate": false,
		  "share": "disabled",
		  "permission": { "bash": "deny", "edit": "deny", "webfetch": "deny", "read": "deny",
		    "glob": "deny", "grep": "deny", "list": "deny", "task": "deny" },
		  "tools": { "bash": false, "edit": false, "write": false, "patch": false, "webfetch": false,
		    "read": false, "glob": false, "grep": false, "list": false, "task": false,
		    "todowrite": false, "todoread": false },
		  "mcp": {
		    "envdump": { "type": "local", "enabled": true,
		      "command": ["sh", "$HERE/../h0.2-opencode/envdump.sh", "$OUT/mcp-sh-env.txt"] },
		    "npxfake": { "type": "local", "enabled": true,
		      "command": ["npx", "--yes", "$HERE/fake-mcp", "$OUT/mcp-npx-env.txt"] }
		  }
		}
	EOF
	(cd "$PROJ" && git init -q && git add README.md opencode.json && git commit -q -m init) || exit 1
}

# ---------------------------------------------------------------------------
# Snapshots.
# ---------------------------------------------------------------------------

snap_all() { # <name>
	for _r in $H04_SNAP_ROOTS; do
		_label=${_r%%=*} _path=${_r#*=}
		_depth=""
		case " ${H04_SNAP_SHALLOW:-} " in *" $_label "*) _depth=3 ;; esac
		# shellcheck disable=SC2086 # H04_SNAP_PRUNE is a list of paths/globs
		H04_SNAP_MAXDEPTH=$_depth h04_snap "$SNAP/$1-$_label.txt" "$_path" "$DEST" "$WS/.ditto" ${H04_SNAP_PRUNE:-}
		echo "$_label $(wc -l <"$SNAP/$1-$_label.txt" | tr -d ' ') entries sha256=$(h04_snap_hash "$SNAP/$1-$_label.txt")" >>"$SNAP/$1.hashes"
	done
}

diff_all() { # <from> <to>
	_o="$LOGS/diff-$1-$2.txt"
	: >"$_o"
	for _r in $H04_SNAP_ROOTS; do
		_label=${_r%%=*}
		h04_diff "$SNAP/$1-$_label.txt" "$SNAP/$2-$_label.txt" | sed "s|^|$_label\t|" >>"$_o"
	done
	_dn=$(wc -l <"$_o" | tr -d ' ')
	result "diff-$1-$2" INFO "$_dn change(s) outside .ditto ($(cut -f2 "$_o" | sort | uniq -c | tr -s ' ' | tr '\n' ',' | sed 's/,$//')); see $_o"
}

# ---------------------------------------------------------------------------
# Session driver (H0.3 pty.lua, with its own throwaway HOME/XDG).
# ---------------------------------------------------------------------------

# H04_TRACE: optional command prefix (strace) for the whole session.
helper_nvim() {
	mkdir -p "$DEST/driver/tmp"
	# shellcheck disable=SC2086 # H04_TRACE is a command prefix
	${H04_TRACE:-} env HOME="$DEST/driver" XDG_CONFIG_HOME="$DEST/driver/config" XDG_DATA_HOME="$DEST/driver/data" \
		XDG_STATE_HOME="$DEST/driver/state" XDG_CACHE_HOME="$DEST/driver/cache" TMPDIR="$DEST/driver/tmp" \
		XDG_RUNTIME_DIR= "$NVIM_BIN" --clean --headless -n -i NONE "$@"
}

sum_stdin() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}

write_env() { # <file>
	{
		echo "HOME=$HOME"
		echo "USER=${USER:-$(id -un)}"
		echo "LOGNAME=${USER:-$(id -un)}"
		echo "SHELL=$SESSION_SHELL"
		echo "TERM=xterm-256color"
		echo "LANG=${LANG:-C.UTF-8}"
		echo "PATH=$BASE_PATH"
		[ -n "${TMPDIR:-}" ] && echo "TMPDIR=$TMPDIR"
		[ "$(uname -s)" = Darwin ] && echo "BASH_SILENCE_DEPRECATION_WARNING=1"
		[ -n "${H04_PTY_ENV_EXTRA:-}" ] && printf '%s\n' "$H04_PTY_ENV_EXTRA" | tr ' ' '\n'
	} >"$1"
}

# steps_session <tag> <with-install: 1|0> — what the user types in the session.
steps_session() {
	_t=$1
	echo "send env | LC_ALL=C sort > '$OUT/$_t-session.env'"
	if [ "$PROFILE" = full ]; then
		if [ "$2" = 1 ]; then
			echo "send nvim --headless '+Lazy! restore' +qa > '$OUT/$_t-restore.log' 2>&1; touch '$OUT/$_t-restore.done'"
			echo "wait $OUT/$_t-restore.done 900000"
			echo "send nvim --headless '+Lazy! load mason.nvim' '+MasonInstall stylua@$H04_STYLUA_VERSION' +qa > '$OUT/$_t-mason.log' 2>&1; touch '$OUT/$_t-mason.done'"
			echo "wait $OUT/$_t-mason.done 600000"
		fi
		echo "send H04_OUT='$OUT' H04_TAG=$_t nvim \"+lua dofile('$HERE/lua/session.lua')\"; touch '$OUT/$_t-nvim.exit'"
		echo "wait $OUT/$_t-nvim.exit 300000"
	fi
	echo "send H04_OC_RUN=${H04_OC_RUN:-0} sh '$HERE/oc-session.sh' '$OUT' $_t"
	echo "wait $OUT/$_t-oc.done 900000"
	echo "send opencode; touch '$OUT/$_t-octui.exit'"
	# ctrl+c quits the TUI; repeated because a slow (emulated) start may miss
	# the first one. Extra ones land on an idle shell prompt: harmless.
	echo "sleep 20000"
	for _k in 1 2 3; do
		echo 'key \3'
		echo "sleep 5000"
	done
	echo "wait $OUT/$_t-octui.exit 60000"
	if [ "$PROFILE" = full ]; then
		echo "send lazygit; touch '$OUT/$_t-lazygit.exit'"
		echo "sleep 6000"
		echo "key q"
		echo "wait $OUT/$_t-lazygit.exit 20000"
	fi
	# A shell the user opens by hand inside the session: it loads the user's rc.
	echo "send \"\$SHELL\" -i"
	echo "sleep 3000"
	echo "send echo nested-history-marker-$_t"
	echo "send exit"
	echo "sleep 2000"
	echo "send echo session-history-marker-$_t"
	echo "send exit"
	echo "exit 30000"
}

# strace_writes <strace-log> — write-like file syscalls that succeeded, on
# paths outside <dest> and .ditto: "<syscall> <path>", unique (strace-writes.awk).
strace_writes() {
	awk -v start="$PWD" -v dest="$DEST/" -v ditto="$WS/.ditto/" -f "$HERE/strace-writes.awk" "$1" | LC_ALL=C sort -u
}

run_session() { # <tag> <with-install>
	_t=$1
	write_env "$LOGS/session-$_t.env"
	steps_session "$_t" "$2" >"$LOGS/steps-$_t"
	_inw=""
	if [ -n "${H04_INOTIFY:-}" ] && command -v inotifywait >/dev/null 2>&1; then
		# shellcheck disable=SC2086 # list of dirs
		inotifywait -m -r -q -e create,moved_to,delete,modify,attrib --timefmt %s --format '%T %e %w%f' \
			-o "$LOGS/inotify-$_t.txt" $H04_INOTIFY &
		_inw=$!
		sleep 2
	fi
	_trace=""
	[ "${H04_STRACE:-0}" = 1 ] &&
		_trace="strace -f -qq -y -e trace=file,fchdir,clone,clone3,fork,vfork -o $LOGS/strace-$_t.txt"
	H04_TRACE=$_trace helper_nvim -l "$H03_DIR/lua/pty.lua" "$LOGS/session-$_t.env" "$PROJ" "$LOGS/steps-$_t" \
		"$LOGS/pty-$_t.txt" "$DITTO_ROOT/shell/session" 2>>"$LOGS/pty.log"
	_rc=$?
	[ -n "$_inw" ] && { sleep 1; kill "$_inw" 2>/dev/null; wait "$_inw" 2>/dev/null; }
	if [ "$_rc" = 0 ]; then
		result "session-$_t" PASS "session script completed (pty)"
	else
		result "session-$_t" FAIL "session script did not complete (see $LOGS/pty-$_t.txt, $LOGS/pty.log)"
	fi
	if [ -f "$LOGS/strace-$_t.txt" ]; then
		strace_writes "$LOGS/strace-$_t.txt" >"$LOGS/strace-writes-$_t.txt"
		result "strace-$_t" INFO "$(wc -l <"$LOGS/strace-writes-$_t.txt" | tr -d ' ') write syscall(s) outside <dest> and .ditto; see $LOGS/strace-writes-$_t.txt"
	fi
	[ -f "$LOGS/inotify-$_t.txt" ] &&
		result "inotify-$_t" INFO "$(wc -l <"$LOGS/inotify-$_t.txt" | tr -d ' ') event(s) in ${H04_INOTIFY}; see $LOGS/inotify-$_t.txt"
	return 0
}

report_session() { # <tag>
	_t=$1
	if [ "$PROFILE" = full ]; then
		for _s in restore mason; do
			[ -f "$OUT/$_t-$_s.done" ] && result "$_t-$_s" INFO "$(grep -ciE 'error|fail' "$OUT/$_t-$_s.log" 2>/dev/null) error line(s) in $_t-$_s.log"
		done
		if [ -f "$OUT/$_t-nvim.json" ]; then
			result "$_t-nvim" INFO "$(tr -d '\n' <"$OUT/$_t-nvim.json" | sed 's/"lazygit_screen":\[[^]]*\],//' | cut -c1-900)"
		else
			result "$_t-nvim" FAIL "no $_t-nvim.json"
		fi
	fi
	result "$_t-opencode" INFO "$(grep -E '^(\$|exit=|#)' "$OUT/$_t-opencode.log" 2>/dev/null | tr '\n' ' ' | cut -c1-900)"
	for _m in sh npx; do
		if [ -f "$OUT/mcp-$_m-env.txt" ]; then
			result "$_t-mcp-$_m" INFO "MCP started; env: $(grep -E '^(HOME|TMPDIR|XDG_CACHE_HOME|npm_config_cache)=' "$OUT/mcp-$_m-env.txt" | tr '\n' ' ')"
			mv "$OUT/mcp-$_m-env.txt" "$OUT/$_t-mcp-$_m-env.txt"
		else
			result "$_t-mcp-$_m" INFO "MCP did not record its environment"
		fi
	done
}

# ---------------------------------------------------------------------------
# Run.
# ---------------------------------------------------------------------------

make_fixtures
_gitcfg_before=$(cat "$HOME/.config/git/config" "$HOME/.config/git/ignore" | sum_stdin)
snap_all S0
: >"$LOGS/marker-S0"
sleep 1

# --- Install (what `ditto up` would do). ---
h03_paths "$WS/.ditto" || exit 1
h04_install_tools >"$LOGS/install.log" 2>&1 || { cat "$LOGS/install.log" >&2; exit 1; }
H04_NODE_BIN=$(h04_install_node "$DL" 2>>"$LOGS/install.log") || { cat "$LOGS/install.log" >&2; exit 1; }
H03_RUNTIME_PATH="$H04_NODE_BIN"
NVIM_BIN=$(h03_tool nvim)
h03_write_wrappers || exit 1
cat >"$DITTO_ROOT/config/lazygit/config.yml" <<-EOF
	update:
	  method: never
	disableStartupPopups: true
	git:
	  autoFetch: false
EOF
if [ "$PROFILE" = full ]; then
	h04_install_starter "$DEST" >"$LOGS/starter.log" 2>&1 || { cat "$LOGS/starter.log" >&2; exit 1; }
fi
h04_write_opencode_wrapper "$(h03_tool opencode)" "$H04_NODE_BIN" || exit 1
h03_write_session || exit 1
result install INFO "tools: $(find "$DITTO_ROOT/bin" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' ')$([ -n "$H04_NODE_BIN" ] && echo "; node $H04_NODE_VERSION (sha256 OK)")"
snap_all S1
diff_all S0 S1

# --- Session A (current wrappers) and B (proposed). ---
# (No leading underscore: the library functions use _-prefixed globals.)
phase_prev=S1
phase_idx=2
for phase in $H04_PHASES; do
	if [ "$phase" = B ]; then
		h04_apply_proposed || exit 1
	fi
	# The first session also runs `Lazy! restore` and the Mason install.
	phase_install=0
	[ "$phase_idx" = 2 ] && phase_install=1
	run_session "$phase" "$phase_install"
	report_session "$phase"
	if [ "$phase_install" = 1 ] && [ "$PROFILE" = full ]; then
		h04_verify_mason "$DL" >"$LOGS/mason-verify.txt" 2>&1
		mason_rc=$?
		result "$phase-mason-sha256" "$([ "$mason_rc" = 0 ] && echo PASS || echo FAIL)" "$(grep -E '^(OK|MISMATCH)' "$LOGS/mason-verify.txt" | tr '\n' ' ')"
	fi
	snap_all "S$phase_idx"
	diff_all "$phase_prev" "S$phase_idx"
	phase_prev="S$phase_idx"
	phase_idx=$((phase_idx + 1))
done

# History files: where did the session and the nested shell write?
for _f in "$HOME/.zsh_history" "$HOME/.bash_history" "$DITTO_ROOT/state/shell/zsh_history" "$DITTO_ROOT/state/shell/bash_history"; do
	[ -f "$_f" ] && result history INFO "${_f}: $(grep -o 'nested-history-marker-[AB]\|session-history-marker-[AB]' "$_f" | sort -u | tr '\n' ' ')"
done
for _f in "$HOME/.zsh_sessions"/*.history "$WS/.ditto/shell/zsh/.zsh_history" "$WS/.ditto/shell/zsh/.zsh_sessions"/*.history; do
	[ -f "$_f" ] && result zsh-sessions INFO "${_f}: $(grep -o 'nested-history-marker-[AB]\|session-history-marker-[AB]' "$_f" | sort -u | tr '\n' ' ')"
done

if [ "${H04_KEEP_WS:-0}" = 1 ]; then
	result keep-ws INFO "workspace kept for manual checks: $WS (session: $DITTO_ROOT/shell/session)"
	echo "== $(grep -c ' PASS ' "$RESULTS") PASS, $FAILS FAIL, $(grep -c ' INFO ' "$RESULTS") INFO" | tee -a "$RESULTS"
	[ "$FAILS" -eq 0 ]
	exit
fi

# --- Delete the workspace and check nothing attributable remains. ---
# Only the workspace this script created: under <dest>, the Docker /w, or the
# sibling <scratch>/w of macos.sh.
case "$WS" in
"$DEST"/w | /w | "${DEST%/*}/w") ;;
*) echo "refusing to delete unexpected workspace path $WS" >&2; exit 1 ;;
esac
[ -d "$WS/.ditto" ] || { echo "no $WS/.ditto; refusing to delete" >&2; exit 1; }
chmod -R u+w "$WS/.ditto" 2>/dev/null
rm -rf "${WS:?}/.ditto" "${WS:?}/proj"
snap_all S9
diff_all S0 S9
_gitcfg_after=$(cat "$HOME/.config/git/config" "$HOME/.config/git/ignore" | sum_stdin)
if [ "$_gitcfg_before" = "$_gitcfg_after" ] && [ -f "$HOME/.config/git/config" ]; then
	result git-symlink-target PASS "user ~/.config/git intact after deleting the workspace (.ditto/config/git was a symlink to it)"
else
	result git-symlink-target FAIL "user ~/.config/git changed or gone"
fi

echo "== $(grep -c ' PASS ' "$RESULTS") PASS, $FAILS FAIL, $(grep -c ' INFO ' "$RESULTS") INFO" | tee -a "$RESULTS"
[ "$FAILS" -eq 0 ]
