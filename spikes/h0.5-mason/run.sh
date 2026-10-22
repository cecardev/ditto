#!/bin/sh
# shellcheck disable=SC2031 # ditto_mise sets HOME/TMPDIR only in its own subshell, on purpose
# shellcheck disable=SC2015 # result() always returns 0, so A && result ... || result ... is safe
# shellcheck disable=SC2016 # single-quoted $ in probe commands, on purpose
# Spike H0.5 — headless Mason prewarm (plus nvim-treesitter parsers and the
# blink.cmp binary) with the runtimes of mise only in the PATH of the nvim
# wrapper, and LSP start-up per platform. Reproducible end to end:
#
#   sh run.sh <dest> [test|lock|mise-lock]
#
#   test (default)  install (mise + H0.1 lock + runtimes lock), wrappers,
#                   starter, `Lazy! restore`, prewarm, then the checks below.
#   lock            regenerate starter/lazy-lock.json (Lazy! sync); prints the
#                   path of the new lock (copy it by hand).
#   mise-lock       regenerate mise.lock (runtimes, 6 platforms + the
#                   glibc-217 Node flavour); prints its path.
#
# <dest> is scratch space: <dest>/ws/.ditto is the workspace, <dest>/logs the
# logs, results.txt and the JSON reports. Keep <dest> short (< 60 chars):
# Neovim fails with ENAMETOOLONG on long paths (H0.3, "Rutas largas").
#
# $HOME MUST be disposable: the script writes user fixtures (~/.bashrc,
# ~/.npmrc, ~/.config/pip, ~/.config/go/env, ~/hostbin) there. It refuses to
# run unless DITTO_SPIKE_DISPOSABLE_HOME=1 (docker.sh/macos.sh set it).
#
# Environment:
#   H05_CONTROL=1         also run the control: wrapper without the cache
#                         variables, a few npm/pip/go packages, list the writes
#                         outside .ditto (default 1).
#   H05_BASEDPYRIGHT=1    also prewarm/check basedpyright (pip) (default 1).
#   H05_LSP_TIMEOUT=<ms>  per-LSP attach timeout (default 120000).
#
# Output: "RESULT <id> <PASS|FAIL|XFAIL|INFO|SKIP> <detail>" lines (also in
# <dest>/logs/results.txt). Exit 1 if any FAIL.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
H05_DIR=$HERE
. "$HERE/lib.sh"

[ $# -ge 1 ] || { echo "usage: $0 <dest> [test|lock|mise-lock]" >&2; exit 2; }
[ "${DITTO_SPIKE_DISPOSABLE_HOME:-0}" = 1 ] || {
	echo "refusing: \$HOME must be disposable (set DITTO_SPIKE_DISPOSABLE_HOME=1; see macos.sh/docker.sh)" >&2
	exit 2
}
mkdir -p "$1"
DEST=$(cd "$1" && pwd -P)
MODE=${2:-test}
_tmpd=${TMPDIR:-/tmp}
if [ "${#DEST}" -gt 60 ] || [ "${#_tmpd}" -gt 60 ]; then
	echo "refusing: <dest> and \$TMPDIR must be at most 60 characters (got ${#DEST} / ${#_tmpd})" >&2
	exit 2
fi
H05_CONTROL=${H05_CONTROL:-1}
H05_BASEDPYRIGHT=${H05_BASEDPYRIGHT:-1}
H05_LSP_TIMEOUT=${H05_LSP_TIMEOUT:-120000}
WS="$DEST/ws"
LOGS="$DEST/logs"
PROJ="$DEST/proj"
mkdir -p "$WS" "$LOGS"
RESULTS="$LOGS/results.txt"
: >"$RESULTS"
FAILS=0

for _t in git curl tar find awk sed sort du cmp bash; do
	command -v "$_t" >/dev/null 2>&1 || { echo "run.sh needs '$_t' on PATH" >&2; exit 2; }
done

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

now() { date +%s; }
# kb <path> — disk usage in KiB (0 if missing).
kb() { if [ -e "$1" ]; then du -sk "$1" 2>/dev/null | cut -f1; else echo 0; fi; }
mb() { echo $(($(kb "$1") / 1024)); }

# with_timeout <seconds> <cmd...> — portable timeout (no coreutils on macOS).
with_timeout() {
	_s=$1
	shift
	"$@" &
	_pid=$!
	# The killer must not hold the caller's stdout (a $(...) would wait for it).
	(sleep "$_s" && kill "$_pid" 2>/dev/null) >/dev/null 2>&1 </dev/null &
	_killer=$!
	wait "$_pid"
	_rc=$?
	kill "$_killer" 2>/dev/null
	wait "$_killer" 2>/dev/null
	return "$_rc"
}

# ---------------------------------------------------------------------------
# Fixtures in the disposable $HOME (before the marker): the user's rc puts a
# fake host node/python3 in PATH, plus package-manager config the Mason
# children should (or should not) see.
# ---------------------------------------------------------------------------

make_fixtures() {
	for _f in .bashrc .npmrc .config/pip .config/go hostbin; do
		if [ -e "$HOME/$_f" ] || [ -L "$HOME/$_f" ]; then
			echo "refusing: \$HOME/$_f already exists; run.sh only writes its fixtures into an empty, disposable \$HOME" >&2
			exit 2
		fi
	done
	mkdir -p "$HOME/hostbin" "$HOME/.config/pip" "$HOME/.config/go"
	for _b in node python3; do
		printf '#!/bin/sh\necho "host-%s"\n' "$_b" >"$HOME/hostbin/$_b"
		chmod 0755 "$HOME/hostbin/$_b"
	done
	cat >"$HOME/.bashrc" <<-'EOF'
		export PATH="$HOME/hostbin:$PATH"
	EOF
	# Harmless markers: they change no install, only what `config` reports.
	printf '[global]\ntimeout = 61\n' >"$HOME/.config/pip/pip.conf"
	printf 'GOPRIVATE=spike.example.invalid\n' >"$HOME/.config/go/env"
	printf 'fetch-retries=7\n' >"$HOME/.npmrc"
	# macOS: pip and go read their user config from ~/Library/Application Support.
	if [ "$(uname -s)" = Darwin ]; then
		mkdir -p "$HOME/Library/Application Support/go"
		printf 'GOPRIVATE=spike.example.invalid\n' >"$HOME/Library/Application Support/go/env"
	fi
}

# host_env <cmd...> — the user's environment (HOME, PATH...) and nothing else.
host_env() {
	env -i HOME="$HOME" USER="${USER:-spike}" LOGNAME="${USER:-spike}" SHELL=/bin/bash TERM=xterm-256color \
		LANG="${LANG:-C.UTF-8}" PATH="$BASE_PATH" TMPDIR="$_tmpd" "$@"
}

# ditto_run <cmd...> — how ditto (Go) would run a tool before the session:
# the user's environment plus .ditto/bin first in PATH and DITTO_ROOT.
ditto_run() {
	host_env PATH="$DITTO_ROOT/bin:$BASE_PATH" DITTO_ROOT="$DITTO_ROOT" "$@"
}

# in_session <cmd...> — runs cmd inside the ditto subshell (bash session rc of
# H0.3: user rc first, then .ditto/bin in front), as a user typing `nvim`.
in_session() {
	ditto_run bash --noprofile --rcfile "$DITTO_ROOT/shell/bashrc" -i -c 'exec "$@"' bash "$@" 2>>"$LOGS/session-stderr.log"
}

setup() { # <ws>
	h05_paths "$1/.ditto" || exit 1
	_t0=$(now)
	h05_install_tools >"$LOGS/install.log" 2>&1 || { tail -n 40 "$LOGS/install.log" >&2; result T1-install FAIL "mise install --locked (see logs/install.log)"; exit 1; }
	result T1-install PASS "mise install --locked: H0.3 tools + node $H05_V_NODE$( [ -n "$(h05_node_flavor)" ] && echo " ($(h05_node_flavor))") go $H05_V_GO python $H05_V_PYTHON in $(($(now) - _t0)) s"
	NVIM_BIN=$(h03_tool nvim)
	h05_write_wrappers || exit 1
	h03_write_session || exit 1
	mkdir -p "$DITTO_ROOT/config/lazygit"
	printf 'update:\n  method: never\ndisableStartupPopups: true\ngit:\n  autoFetch: false\n' >"$DITTO_ROOT/config/lazygit/config.yml"
}

# helper_nvim <args...> — bare nvim for spike tooling, own throwaway HOME/XDG.
helper_nvim() {
	mkdir -p "$DEST/driver/tmp"
	HOME="$DEST/driver" XDG_CONFIG_HOME="$DEST/driver/config" XDG_DATA_HOME="$DEST/driver/data" \
		XDG_STATE_HOME="$DEST/driver/state" XDG_CACHE_HOME="$DEST/driver/cache" TMPDIR="$DEST/driver/tmp" \
		"$NVIM_BIN" --clean --headless -n -i NONE "$@"
}

# ---------------------------------------------------------------------------
# mise-lock mode: runtimes for every platform (sha256 per asset).
# ---------------------------------------------------------------------------

if [ "$MODE" = mise-lock ]; then
	ditto_mise_paths "$WS/.ditto"
	ditto_mise_bootstrap || exit 1
	printf '[tools]\n"core:node" = "%s"\n"core:go" = "%s"\n"core:python" = "%s"\n\n[settings.python]\ncompile = false\n' \
		"$H05_V_NODE" "$H05_V_GO" "$H05_V_PYTHON" >"$DITTO_MISE_CONFIG"
	rm -f "$DITTO_MISE_LOCK"
	ditto_mise lock --global --platform linux-x64,linux-arm64,linux-x64-musl,linux-arm64-musl,macos-x64,macos-arm64 || exit 1
	cp "$DITTO_MISE_LOCK" "$DEST/mise.lock"
	echo "$DEST/mise.lock"
	exit 0
fi

# mise-lock-217 mode (Linux x86_64 only): adds the entry of the unofficial
# glibc-217 Node build to the existing mise.lock. Locked from macOS, mise
# writes a source-build entry without checksum for this flavour (see
# RESULTS.md); locked natively it gets the binary URL and its sha256.
if [ "$MODE" = mise-lock-217 ]; then
	[ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] || { echo "mise-lock-217 runs on Linux x86_64 only" >&2; exit 2; }
	ditto_mise_paths "$WS/.ditto"
	ditto_mise_bootstrap || exit 1
	printf '[tools]\n"core:node" = "%s"\n\n[settings.node]\nflavor = "glibc-217"\nmirror_url = "https://unofficial-builds.nodejs.org/download/release/"\n' \
		"$H05_V_NODE" >"$DITTO_MISE_CONFIG"
	cp "$HERE/mise.lock" "$DITTO_MISE_LOCK"
	ditto_mise lock --global --platform linux-x64 core:node || exit 1
	cp "$DITTO_MISE_LOCK" "$LOGS/mise.lock"
	echo "$LOGS/mise.lock"
	exit 0
fi

# ---------------------------------------------------------------------------
# lock mode: lazy-lock.json for this starter (extras included).
# ---------------------------------------------------------------------------

if [ "$MODE" = lock ]; then
	make_fixtures
	setup "$WS"
	_tmp="$DEST/starter-nolock"
	rm -rf "$_tmp"
	cp -R "$HERE/starter" "$_tmp"
	rm -f "$_tmp/lazy-lock.json"
	H03_ALLOW_UNPINNED_LAZY=1 h03_install_starter "$_tmp" >"$LOGS/starter.log" 2>&1 || { cat "$LOGS/starter.log" >&2; exit 1; }
	ditto_run nvim --headless "+Lazy! sync" +qa >"$LOGS/lazy-sync.log" 2>&1
	cp "$DITTO_ROOT/config/nvim/lazy-lock.json" "$DEST/lazy-lock.json"
	echo "$DEST/lazy-lock.json"
	exit 0
fi

# ---------------------------------------------------------------------------
# Test mode.
# ---------------------------------------------------------------------------

[ -f "$HERE/starter/lazy-lock.json" ] || { echo "starter/lazy-lock.json missing: run '$0 <dest> lock' first" >&2; exit 2; }
make_fixtures
result T0-host INFO "$(uname -s) $(uname -m); libc: $(ditto_libc); git $(git --version | cut -d' ' -f3); cc: $(command -v cc || echo none); unzip: $(command -v unzip || echo none)"

# Writes outside .ditto are measured from here on.
MARKER="$LOGS/marker"
: >"$MARKER"
sleep 1

setup "$WS"
h03_install_starter "$HERE/starter" >"$LOGS/starter.log" 2>&1 || { cat "$LOGS/starter.log" >&2; exit 1; }
MASON="$DITTO_ROOT/data/nvim/mason"

# --- T2: Lazy! restore (H0.3 command). ---
_t0=$(now)
if ditto_run nvim --headless "+Lazy! restore" +qa >"$LOGS/lazy-restore.log" 2>&1; then
	_n=$(grep -c '"commit"' "$DITTO_ROOT/config/nvim/lazy-lock.json")
	result T2-lazy-restore PASS "$_n plugins restored in $(($(now) - _t0)) s"
else
	result T2-lazy-restore FAIL "exit $? (see logs/lazy-restore.log)"
fi
cmp -s "$HERE/starter/lazy-lock.json" "$DITTO_ROOT/config/nvim/lazy-lock.json" &&
	result T2-lock-unchanged PASS "lazy-lock.json unchanged" ||
	result T2-lock-unchanged FAIL "lazy-lock.json changed by Lazy! restore"

# --- T3: prewarm (the command proposed for arch.md §9). ---
# One headless run: parsers (wait), blink.cmp binary (wait), Mason packages of
# the active extras (MasonInstall, blocking in headless). See lua/prewarm.lua.
prewarm() { # <tag> [extra env...]
	_tag=$1
	shift
	_t0=$(now)
	ditto_run env H05_REPORT="$LOGS/prewarm-$_tag.json" "$@" \
		nvim --headless "+luafile $HERE/lua/prewarm.lua" >"$LOGS/prewarm-$_tag.log" 2>&1
	_rc=$?
	_dt=$(($(now) - _t0))
	cp "$DITTO_ROOT/state/nvim/mason.log" "$LOGS/mason.log" 2>/dev/null
	if [ "$_rc" = 0 ]; then
		result "T3-prewarm-$_tag" PASS "exit 0 in $_dt s; $(sed -n 's/.*"summary": *"\([^"]*\)".*/\1/p' "$LOGS/prewarm-$_tag.json")"
	else
		result "T3-prewarm-$_tag" FAIL "exit $_rc after $_dt s (see logs/prewarm-$_tag.log): $(grep -iE 'error|fail' "$LOGS/prewarm-$_tag.log" | head -n 3 | tr '\n' ' ')"
	fi
}
prewarm main
if [ "$H05_BASEDPYRIGHT" = 1 ]; then
	# Same command with the other Python LSP selected (vim.g.lazyvim_python_lsp):
	# only basedpyright (pip) is added.
	prewarm basedpyright H05_PYTHON_LSP=basedpyright
fi
# Idempotence: a second run installs nothing and is fast.
prewarm again

# --- Sizes. ---
{
	echo "mason_total_mb $(mb "$MASON")"
	for _p in "$MASON"/packages/*; do
		[ -d "$_p" ] && echo "mason_pkg_mb ${_p##*/} $(mb "$_p")"
	done
	echo "parsers_mb $(mb "$DITTO_ROOT/data/nvim/site")"
	echo "lazy_plugins_mb $(mb "$DITTO_ROOT/data/nvim/lazy")"
	echo "blink_mb $(mb "$DITTO_ROOT/data/nvim/lazy/blink.cmp/target")"
	echo "mise_installs_mb $(mb "$DITTO_ROOT/mise/installs")"
	for _r in node go python; do
		echo "runtime_mb $_r $(mb "$DITTO_ROOT/mise/installs/$_r")"
	done
	echo "cache_npm_mb $(mb "$DITTO_ROOT/cache/npm")"
	echo "cache_pip_mb $(mb "$DITTO_ROOT/cache/pip")"
	echo "cache_go_mb $(mb "$DITTO_ROOT/cache/go")"
	echo "data_go_mb $(mb "$DITTO_ROOT/data/go")"
	echo "ditto_total_mb $(mb "$DITTO_ROOT")"
} >"$LOGS/sizes.txt"
result T3-sizes INFO "$(tr '\n' ';' <"$LOGS/sizes.txt" | sed 's/;/; /g')"

# --- T4: everything Mason installed lives in .ditto/data/nvim/mason. ---
if [ -d "$MASON/packages" ] && [ -d "$MASON/bin" ]; then
	_out=""
	for _l in "$MASON"/bin/*; do
		# Links are relative (../packages/...): resolve the target directory.
		_r=$(readlink "$_l" 2>/dev/null || echo "$_l")
		case "$_r" in /*) _t=$_r ;; *) _t="$MASON/bin/$_r" ;; esac
		_t="$(cd "$(dirname "$_t")" 2>/dev/null && pwd -P)/${_t##*/}"
		case "$_t" in "$MASON"/*) ;; *) _out="$_out ${_l##*/}->$_t" ;; esac
	done
	[ -z "$_out" ] && result T4-mason-dir PASS "$(find "$MASON/packages" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ') packages and $(find "$MASON/bin" -mindepth 1 | wc -l | tr -d ' ') bin links, all under .ditto/data/nvim/mason" ||
		result T4-mason-dir FAIL "links outside mason:$_out"
else
	result T4-mason-dir FAIL "no $MASON/packages"
fi

# --- T5: each Mason binary runs (glibc!) and the glibc it needs. ---
# max_glibc <dir> — highest GLIBC_x.y symbol version referenced by any ELF file.
max_glibc() {
	find "$1" -type f \( -perm -u+x -o -name '*.so' -o -name '*.so.*' -o -name '*.node' \) 2>/dev/null |
		while IFS= read -r _f; do
			head -c 4 "$_f" 2>/dev/null | grep -q 'ELF' && grep -ao 'GLIBC_2\.[0-9][0-9]*' "$_f" 2>/dev/null
		done | sort -u -t. -k2,2n | tail -n 1
}
RT_PATH=$(h05_runtime_path)
: >"$LOGS/bins.txt"
for _l in "$MASON"/bin/*; do
	[ -e "$_l" ] || continue
	_n=${_l##*/}
	# Language servers are checked for real in T6; here any output that is not
	# a loader error (missing GLIBC_x, wrong arch) means the binary runs.
	case "$_n" in
	gopls) _arg=version ;;
	goimports) _arg=-h ;;
	*) _arg=--version ;;
	esac
	# Same PATH as inside nvim: runtimes + mason/bin (Mason prepends it).
	_o=$(with_timeout 60 env PATH="$MASON/bin:$RT_PATH:$BASE_PATH" HOME="$DEST/driver" "$_l" $_arg </dev/null 2>&1 | head -n 3 | tr '\n' ' ')
	_rc=$?
	echo "$_n|$_o" >>"$LOGS/bins.txt"
	if echo "$_o" | grep -qE 'GLIBC_|GLIBCXX_|not found|cannot execute|Exec format'; then
		result "T5-bin-$_n" FAIL "$_o"
	else
		result "T5-bin-$_n" PASS "$(echo "$_o" | cut -c1-100)"
	fi
done
# T5b: a github-release binary built for a newer glibc (stylua's -gnu build)
# can be replaced by its musl build with Mason's own --target option.
if grep -qE '^stylua\|.*GLIBC_' "$LOGS/bins.txt"; then
	if [ "$(ditto_arch)" = x64 ]; then
		ditto_run nvim --headless "+lua require('lazy').load({ plugins = { 'mason.nvim' } })" \
			"+MasonInstall --force --target=linux_x64 stylua" +qa >"$LOGS/stylua-musl.log" 2>&1
		_o=$(with_timeout 60 "$MASON/bin/stylua" --version </dev/null 2>&1 | head -n 2 | tr '\n' ' ')
		if echo "$_o" | grep -q '^stylua '; then
			result T5-stylua-musl PASS "MasonInstall --force --target=linux_x64 stylua (static musl build): $_o"
		else
			result T5-stylua-musl FAIL "musl build: $_o"
		fi
	else
		result T5-stylua-musl SKIP "the registry has no musl stylua build for arm64 (only linux_arm64_gnu)"
	fi
fi
if [ "$(uname -s)" = Linux ]; then
	for _p in "$MASON"/packages/* "$DITTO_ROOT/data/nvim/lazy/blink.cmp/target" "$DITTO_ROOT/data/nvim/site/parser"; do
		[ -d "$_p" ] || continue
		_g=$(max_glibc "$_p")
		echo "glibc ${_p##*/} ${_g:-none}" >>"$LOGS/sizes.txt"
		result "T5-glibc-${_p##*/}" INFO "max symbol version: ${_g:-none (no glibc-linked ELF: script/static)}"
	done
	for _r in node python go; do
		_g=$(max_glibc "$DITTO_ROOT/mise/installs/$_r")
		result "T5-glibc-runtime-$_r" INFO "max symbol version: ${_g:-none}"
	done
fi

# --- T6: each LSP starts and answers (lsp-check.lua). ---
mkdir -p "$PROJ"
printf 'local M = {}\nfunction M.greet(name)\n  return "hi " .. name\nend\nreturn M\n' >"$PROJ/main.lua"
printf 'def greet(name: str) -> str:\n    return "hi " + name\n\n\nclass Spike:\n    pass\n' >"$PROJ/main.py"
printf '[project]\nname = "spike"\nversion = "0.0.0"\n' >"$PROJ/pyproject.toml"
printf 'module spike\n\ngo 1.22\n' >"$PROJ/go.mod"
printf 'package main\n\nfunc greet(name string) string { return "hi " + name }\n\nfunc main() { _ = greet("x") }\n' >"$PROJ/main.go"
printf '{ "name": "spike", "version": "0.0.0", "private": true }\n' >"$PROJ/package.json"
printf '{ "compilerOptions": { "strict": true, "target": "es2022", "module": "esnext" } }\n' >"$PROJ/tsconfig.json"
printf 'export function greet(name: string): string {\n  return "hi " + name;\n}\nexport class Spike {}\n' >"$PROJ/main.ts"
lsp_check() { # <tag> [extra env...]
	_tag=$1
	shift
	(cd "$PROJ" && in_session env H05_REPORT="$LOGS/lsp-$_tag.json" H05_PROJ="$PROJ" H05_LSP_TIMEOUT="$H05_LSP_TIMEOUT" "$@" \
		nvim --headless "+luafile $HERE/lua/lsp-check.lua") </dev/null >"$LOGS/lsp-$_tag.log" 2>&1
	cp "$DITTO_ROOT/state/nvim/lsp.log" "$LOGS/lsp.log" 2>/dev/null
	if [ ! -f "$LOGS/lsp-$_tag.json" ]; then
		result "T6-lsp-$_tag" FAIL "no report (see logs/lsp-$_tag.log)"
		return
	fi
	# One line per case: file|server|status|ms|detail
	sed -n 's/^CASE //p' "$LOGS/lsp-$_tag.log" | while IFS='|' read -r _f _s _st _ms _d; do
		result "T6-lsp-$_tag-$_f" "$_st" "$_s ${_ms} ms $_d"
	done
}
lsp_check main
[ "$H05_BASEDPYRIGHT" = 1 ] && lsp_check basedpyright H05_PYTHON_LSP=basedpyright H05_ONLY=main.py

# --- T7: who sees which node/python (runtimes only in the nvim wrapper). ---
# probe_rt <file> — the commands each context runs.
PROBE='for b in node python3 python go npm pip3; do printf "%s=%s\n" "$b" "$(command -v "$b" || echo -)"; done; printf "node-out=%s\n" "$(node 2>/dev/null </dev/null --version || echo -)"'
host_env bash --noprofile --rcfile "$HOME/.bashrc" -i -c "$PROBE" >"$LOGS/rt-host.txt" 2>/dev/null
ditto_run bash --noprofile --rcfile "$DITTO_ROOT/shell/bashrc" -i -c "$PROBE" >"$LOGS/rt-session.txt" 2>/dev/null
(cd "$PROJ" && in_session env H05_REPORT="$LOGS/rt-nvim" H05_PROBE="$PROBE" \
	nvim --headless "+luafile $HERE/lua/rt-probe.lua") </dev/null >"$LOGS/rt-nvim.log" 2>&1
if cmp -s "$LOGS/rt-host.txt" "$LOGS/rt-session.txt"; then
	result T7-rt-session PASS "subshell sees the host's node/python3 (or none): $(tr '\n' ' ' <"$LOGS/rt-session.txt")"
else
	result T7-rt-session FAIL "subshell differs from host: host[$(tr '\n' ' ' <"$LOGS/rt-host.txt")] session[$(tr '\n' ' ' <"$LOGS/rt-session.txt")]"
fi
if cmp -s "$LOGS/rt-host.txt" "$LOGS/rt-nvim-shell.txt" 2>/dev/null; then
	result T7-rt-nvim-shell PASS "':!' / system() string (via .host-sh) sees the host's: no mise runtime, no mason/bin"
else
	result T7-rt-nvim-shell FAIL "shell from nvim differs: $(tr '\n' ' ' <"$LOGS/rt-nvim-shell.txt" 2>/dev/null)"
fi
if grep -q "^node=$DITTO_ROOT/mise/installs/" "$LOGS/rt-nvim-argv.txt" 2>/dev/null &&
	grep -q "^python3=$DITTO_ROOT/mise/installs/" "$LOGS/rt-nvim-argv.txt"; then
	result T7-rt-nvim-argv PASS "argument-list children (Mason, LSPs) get the mise runtimes: $(grep -E '^(node|python3|go|node-out)=' "$LOGS/rt-nvim-argv.txt" | sed "s|$DITTO_ROOT|.ditto|g" | tr '\n' ' ')"
else
	result T7-rt-nvim-argv FAIL "argument-list children: $(tr '\n' ' ' <"$LOGS/rt-nvim-argv.txt" 2>/dev/null)"
fi

# --- T8: package-manager config and caches as Mason's children see them. ---
_c="$LOGS/rt-nvim-config.txt"
if [ -f "$_c" ]; then
	result T8-cfg-raw INFO "$(sed "s|$DITTO_ROOT|.ditto|g; s|$HOME|~|g" "$_c" | tr '\n' ' ' | cut -c1-900)"
	grep -q "timeout='61'" "$_c" && result T8-pip-conf PASS "pip (argv child) reads the user's pip.conf (timeout=61)" ||
		result T8-pip-conf FAIL "pip (argv child) does not see the user's pip.conf"
	grep -q '^GOPRIVATE=spike.example.invalid' "$_c" && result T8-go-env PASS "go (argv child) reads the user's go env file (GOPRIVATE)" ||
		result T8-go-env FAIL "go (argv child) misses the user's go env file"
	grep -q '^npm-fetch-retries=7' "$_c" && result T8-npmrc PASS "npm (argv child) reads ~/.npmrc" ||
		result T8-npmrc FAIL "npm (argv child) misses ~/.npmrc"
	_bad=$(grep -E '^(npm-cache|GOMODCACHE|GOCACHE|GOPATH|pip-cache)=' "$_c" | grep -v "=$DITTO_ROOT/" || true)
	[ -z "$_bad" ] && result T8-caches PASS "npm/pip/go caches of argv children under .ditto" ||
		result T8-caches FAIL "caches outside .ditto: $(echo "$_bad" | tr '\n' ' ')"
else
	result T8-cfg FAIL "no $_c"
fi
_s="$LOGS/rt-nvim-shellcfg.txt"
if [ -f "$_s" ] && ! grep -q "$DITTO_ROOT" "$_s"; then
	result T8-shell-caches PASS "':!' sees the host's npm/pip/go settings (no .ditto value): $(sed "s|$HOME|~|g" "$_s" | tr '\n' ' ' | cut -c1-300)"
else
	result T8-shell-caches FAIL "':!' sees ditto values: $(tr '\n' ' ' <"$_s" 2>/dev/null | cut -c1-300)"
fi

# --- T9: nothing written outside .ditto (since the marker). ---
# outside_writes <marker> <out> — new files under $HOME and the temp dirs,
# minus <dest> itself.
outside_writes() {
	for _r in "$HOME" "$_tmpd" /tmp /var/tmp; do
		[ -d "$_r" ] || continue
		_rr=$(cd "$_r" && pwd -P)
		find "$_rr" -newer "$1" 2>/dev/null
	done | awk -v d="$DEST" 'index($0, d) != 1 && $0 != "" ' |
		awk -v h="$(cd "$HOME" && pwd -P)" -v t="$(cd "$_tmpd" && pwd -P)" '$0 != h && $0 != t && $0 != "/tmp" && $0 != "/private/tmp" && $0 != "/var/tmp" && $0 != "/private/var/tmp"' |
		{ if [ -n "${DITTO_SPIKE_WATCH_EXCLUDE:-}" ]; then grep -v -E "$DITTO_SPIKE_WATCH_EXCLUDE"; else cat; fi; } |
		sort -u >"$2"
}
# summarise <file> — "count dir" per directory (HOME shown as ~, 4 levels).
summarise() {
	sed "s|^$(cd "$HOME" && pwd -P)|~|" "$1" | awk -F/ '{ d = $1; for (i = 2; i <= 5 && i <= NF; i++) d = d "/" $i; n[d]++ } END { for (d in n) print n[d], d }' |
		sort -rn | head -n 12 | tr '\n' ';' | sed 's/;/; /g'
}
outside_writes "$MARKER" "$LOGS/outside.txt"
if [ -s "$LOGS/outside.txt" ]; then
	result T9-outside FAIL "$(wc -l <"$LOGS/outside.txt" | tr -d ' ') path(s): $(summarise "$LOGS/outside.txt")"
else
	result T9-outside PASS "nothing new under \$HOME, \$TMPDIR, /tmp, /var/tmp (outside <dest>) after install + prewarm + LSPs"
fi

# --- T10 (control): the H0.3 wrapper + runtimes, without the cache variables. ---
if [ "$H05_CONTROL" = 1 ]; then
	_m2="$LOGS/marker-control"
	: >"$_m2"
	sleep 1
	(
		H05_WRAPPER=bare
		CWS="$DEST/wsc"
		mkdir -p "$CWS/.ditto/data/nvim"
		# Reuse the main install: same mise data and plugins, new wrappers.
		[ -e "$CWS/.ditto/mise" ] || ln -s "$WS/.ditto/mise" "$CWS/.ditto/mise"
		h05_paths "$CWS/.ditto"
		h05_write_wrappers
		[ -e "$CWS/.ditto/data/nvim/lazy" ] || ln -s "$WS/.ditto/data/nvim/lazy" "$CWS/.ditto/data/nvim/lazy"
		h03_install_starter "$HERE/starter" >"$LOGS/control-starter.log" 2>&1
		# One npm, one pip and one go package of Mason.
		ditto_run nvim --headless "+lua require('lazy').load({ plugins = { 'mason.nvim' } })" \
			"+MasonInstall prettier ruff goimports" +qa >"$LOGS/control.log" 2>&1
		printf "\nrc=%s\n" "$?" >>"$LOGS/control.log"
	)
	outside_writes "$_m2" "$LOGS/outside-control.txt"
	# Summarise by top-level directory (npm cache, go modcache, pip cache...).
	_sum=$(summarise "$LOGS/outside-control.txt")
	if [ -s "$LOGS/outside-control.txt" ]; then
		result T10-control XFAIL "without npm_config_cache/PIP_CACHE_DIR/GO*: $(wc -l <"$LOGS/outside-control.txt" | tr -d ' ') path(s) outside .ditto: $_sum ($(tail -n 1 "$LOGS/control.log"))"
	else
		result T10-control INFO "control wrote nothing outside .ditto ($(tail -n 1 "$LOGS/control.log"))"
	fi
fi

echo "SUMMARY $(grep -c '^RESULT [^ ]* PASS' "$RESULTS") PASS, $(grep -c '^RESULT [^ ]* FAIL' "$RESULTS") FAIL, $(grep -c '^RESULT [^ ]* XFAIL' "$RESULTS") XFAIL, $(grep -c '^RESULT [^ ]* SKIP' "$RESULTS") SKIP" | tee -a "$RESULTS"
[ "$(grep -c '^RESULT [^ ]* FAIL' "$RESULTS")" = 0 ]
