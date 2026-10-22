#!/bin/sh
# shellcheck disable=SC2031 # ditto_mise sets HOME/TMPDIR only in its own subshell, on purpose
# Spike H0.1b — can mise alone run the ditto session (option A) or does ditto
# need its own (option B)? See RESULTS.md.
#
#   sh run.sh <dest>
#
# <dest> plays the workspace; .ditto/ is <dest>/.ditto. Every fixture (user
# rc files, a host mise, a simulated conda, git config) lives in per-scenario
# HOMEs under <dest>/homes, so run.sh writes nothing into $HOME. It still runs
# downloaded binaries, so run it through docker.sh or macos.sh (disposable
# HOME/TMPDIR), never with your real HOME.
#
# Tests (numbering of issue #4):
#   T1  bootstrap: env.sh (H0.1) and `mise generate install-script`
#   T2  tools from mise.lock + sh wrappers + session config / rc files
#   T3  session: `mise en`/`exec`/`env` (A) vs rcfile/ZDOTDIR (B), bash/zsh
#   T4  interference: host mise in the rc, conda, rc that rewrites PATH
#   T5  per-tool isolation: XDG only in nvim; git/ssh from :!, :terminal,
#       lazygit; MISE_*/[env] reaching host processes
#   T6  overlap table: each mise feature in the pinned version
#   T7  nothing written outside <dest> ($HOME, /tmp, $TMPDIR)
#
# Environment:
#   DITTO_SPIKE_LOCK=<file>         lock (default ../h0.1-mise-aislado/mise.lock)
#   DITTO_SPIKE_SHELLS="bash zsh"   shells to test (those found on PATH)
#   DITTO_SPIKE_WATCH_EXCLUDE=<re>  noise to ignore in T7 (no default)
#
# Output: "RESULT <id> <PASS|FAIL|INFO|SKIP> <detail>" lines, also stored in
# <dest>/spike-logs/results.txt.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
SPIKE_H01B_DIR=$HERE
. "$HERE/lib.sh"

[ $# -ge 1 ] || { echo "usage: $0 <dest>" >&2; exit 2; }
mkdir -p "$1"
DEST=$(cd "$1" && pwd -P)
LOGS="$DEST/spike-logs"
mkdir -p "$LOGS"
RESULTS="$LOGS/results.txt"
: >"$RESULTS"
LOCK_SRC=${DITTO_SPIKE_LOCK:-$HERE/../h0.1-mise-aislado/mise.lock}
FAILS=0
BASE_PATH=${DITTO_SPIKE_BASE_PATH:-/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}
GIT_FIXTURE_NAME=ditto-fixture-xdg-git
SSH_FIXTURE_USER=ditto-fixture-ssh

for _t in find awk sort git; do
	command -v "$_t" >/dev/null 2>&1 || { echo "run.sh needs '$_t' on PATH" >&2; exit 2; }
done

result() { # <id> <status> <detail...>
	_id=$1 _st=$2
	shift 2
	echo "RESULT $_id $_st $*" | tee -a "$RESULTS"
	[ "$_st" = FAIL ] && FAILS=$((FAILS + 1))
	return 0
}

# check <id> <expected> <got> [detail]
check() {
	if [ "$2" = "$3" ]; then
		result "$1" PASS "${4:-$3}"
	else
		result "$1" FAIL "want '$2' got '$3' ${4:-}"
	fi
}

# --------------------------------------------------------------------------
# T7 helpers (same approach as H0.1)
# --------------------------------------------------------------------------
watch_dirs() {
	echo "$HOME"
	(cd /tmp && pwd -P)
	[ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && (cd "$TMPDIR" && pwd -P)
	return 0
}

exclude_paths() {
	awk -v dest="$DEST/" -v realtmp="$(cd /tmp && pwd -P)" -v home="$HOME" \
		-v tmpd="$(cd "${TMPDIR:-/nonexistent}" 2>/dev/null && pwd -P)" '
		$0 == home || $0 == realtmp || $0 == tmpd || $0 == dest || $0 "/" == dest { next }
		index($0, dest) == 1 { next }
		{ print }
	'
}

# outside_since <marker> — paths newer than <marker> outside <dest>.
outside_since() {
	for _d in $(watch_dirs); do
		find "$_d" -newer "$1" 2>/dev/null | exclude_paths |
			{ if [ -n "${DITTO_SPIKE_WATCH_EXCLUDE:-}" ]; then grep -v -E "$DITTO_SPIKE_WATCH_EXCLUDE"; else cat; fi; } || true
	done
}

# --------------------------------------------------------------------------
# T1 — bootstrap
# --------------------------------------------------------------------------
t1_bootstrap() {
	ditto_mise_paths "$DEST/.ditto"
	D=$DITTO_DIR
	if ditto_mise_bootstrap 2>"$LOGS/bootstrap.txt"; then
		result T1-env.sh PASS "$(ditto_mise_asset) sha256 embedded in env.sh OK"
	else
		result T1-env.sh FAIL "$(cat "$LOGS/bootstrap.txt")"
		return 1
	fi

	# `mise generate bootstrap` is a deprecated alias of install-script.
	_dep=$(ditto_mise generate bootstrap -V "$DITTO_MISE_VERSION" 2>&1 >/dev/null | head -n 1)
	result T1-bootstrap-alias INFO "${_dep:-no deprecation warning}"

	# The script is meant for <project>/bin/mise: it derives the project as
	# the parent of its own directory and keeps data in <project>/.mise.
	_p="$D/boot-test"
	mkdir -p "$_p/bin" "$DEST/homes/boot"
	if ! ditto_mise generate install-script -V "$DITTO_MISE_VERSION" --localize >"$_p/bin/mise" 2>"$LOGS/install-script-gen.txt"; then
		result T1-install-script FAIL "generate: $(head -n 3 "$LOGS/install-script-gen.txt" | tr '\n' ' ')"
		return 0
	fi
	chmod 0755 "$_p/bin/mise"
	result T1-install-script-shebang INFO "$(head -n 1 "$_p/bin/mise") ($(wc -l <"$_p/bin/mise" | tr -d ' ') lines; exports $(grep -c '^ *export MISE_' "$_p/bin/mise") MISE_* only, then exec)"
	if ! command -v bash >/dev/null 2>&1; then
		result T1-install-script FAIL "needs bash (not POSIX sh); bash is not on this host"
		return 0
	fi
	if _v=$(cd "$_p" && HOME="$DEST/homes/boot" bash "$_p/bin/mise" --version 2>"$LOGS/install-script-run.txt"); then
		_bin=$(find "$_p/.mise" -maxdepth 1 -type f -name 'mise-*' | head -n 1)
		_got=$(ditto_sha256 "$_bin")
		_libc=$(ditto_libc)
		# Same binary as the raw release asset? (glibc build on glibc hosts:
		# the script only picks -musl on musl or with MISE_INSTALL_MUSL=1.)
		_os=$(ditto_os) _arch=$(ditto_arch)
		_which=other
		for _a in "mise-v$DITTO_MISE_VERSION-$_os-$_arch" "mise-v$DITTO_MISE_VERSION-$_os-$_arch-musl"; do
			[ "$(ditto_mise_sha256 "$_a" 2>/dev/null)" = "$_got" ] && _which=$_a
		done
		result T1-install-script PASS "$(echo "$_v" | head -n 1); binary ${_bin#"$DEST"/} = asset $_which (libc=$_libc); tarball sha256 embedded in the script"
	else
		result T1-install-script FAIL "$(tail -n 3 "$LOGS/install-script-run.txt" | tr '\n' ' ')"
	fi

	# Tamper test: a different archive under the expected name must be
	# refused (checksum embedded in the script). MISE_TARBALL_URL is honoured
	# for the pinned version, so file:// works offline.
	_libc_sfx=""
	[ "$(ditto_libc)" = musl ] && _libc_sfx=-musl
	_bad="$DEST/boot-tamper/mise-v$DITTO_MISE_VERSION-$(ditto_os)-$(ditto_arch)$_libc_sfx.tar.gz"
	mkdir -p "$DEST/boot-tamper/mise/bin"
	printf '#!/bin/sh\necho tampered\n' >"$DEST/boot-tamper/mise/bin/mise"
	(cd "$DEST/boot-tamper" && tar -czf "$_bad" mise)
	if (cd "$_p" && HOME="$DEST/homes/boot" MISE_INSTALL_EXT=tar.gz MISE_TARBALL_URL="file://$_bad" \
		MISE_INSTALL_PATH="$_p/.mise/tampered" bash "$_p/bin/mise" --version) >"$LOGS/install-script-tamper.txt" 2>&1; then
		result T1-install-script-tamper FAIL "tampered archive accepted: $(tail -n 2 "$LOGS/install-script-tamper.txt" | tr '\n' ' ')"
	elif grep -q 'checksum mismatch' "$LOGS/install-script-tamper.txt" && [ ! -e "$_p/.mise/tampered" ]; then
		result T1-install-script-tamper PASS "$(grep -m 1 'checksum mismatch' "$LOGS/install-script-tamper.txt")"
	else
		result T1-install-script-tamper FAIL "$(tail -n 2 "$LOGS/install-script-tamper.txt" | tr '\n' ' ')"
	fi
}

# --------------------------------------------------------------------------
# T2 — tools, wrappers, session config
# --------------------------------------------------------------------------
t2_prepare() {
	_nv=$(ditto_nvim_tool)
	{
		echo '# Generated by spikes/h0.1b-mise-sesion: subset needed by the session tests.'
		echo '[tools]'
		case "$_nv" in
		aqua:*) echo "\"aqua:neovim/neovim\" = \"$DITTO_V_NVIM\"" ;;
		github:*) echo "\"github:neovim/neovim-releases\" = \"$DITTO_V_NVIM_LEGACY\"" ;;
		esac
		echo "\"github:BurntSushi/ripgrep\" = \"$DITTO_V_RG\""
		echo "\"aqua:jesseduffield/lazygit\" = \"$DITTO_V_LAZYGIT\""
	} >"$DITTO_MISE_CONFIG"
	cp "$LOCK_SRC" "$DITTO_MISE_LOCK"
	if ditto_mise install --locked >"$LOGS/install.txt" 2>&1; then
		result T2-install PASS "mise install --locked (nvim=${_nv:-none}, rg, lazygit)"
	else
		result T2-install FAIL "$(tail -n 5 "$LOGS/install.txt" | tr '\n' ' ')"
		return 1
	fi
	NVIM_BIN=""
	[ -n "$_nv" ] && NVIM_BIN=$(ditto_mise which nvim)
	LG_BIN=$(ditto_mise which lazygit)
	RG_BIN=$(ditto_mise which rg)
	spike_write_wrappers "$D" "$NVIM_BIN" "$LG_BIN" "$RG_BIN"
	spike_write_session_toml "$D" raw
	spike_write_session_toml "$D" clean
	spike_write_session_rc "$D"
	result T2-wrappers INFO "$(cd "$D/bin" && ls -A | tr '\n' ' ')-> exec to mise which paths"
}

# --------------------------------------------------------------------------
# Fixtures: one HOME per scenario.
# --------------------------------------------------------------------------
SCENARIOS="clean conda pathreset hostmise hostmiseaggr"

fake_bin() { # <dir> <name> <id>
	mkdir -p "$1"
	printf '#!/bin/sh\necho %s\n' "$3" >"$1/$2"
	chmod 0755 "$1/$2"
}

# rc_body <scenario> <bash|zsh>
rc_body() {
	echo "# spike fixture: user rc ($1)"
	echo 'export DITTO_SPIKE_RC_LOADED=1'
	case "$1" in
	conda)
		echo '# >>> conda initialize >>> (simulated: what `conda activate base` leaves)'
		echo 'export CONDA_PREFIX="$HOME/miniconda3" CONDA_DEFAULT_ENV=base CONDA_SHLVL=1'
		echo 'export PATH="$HOME/miniconda3/bin:$HOME/miniconda3/condabin:$PATH"'
		echo '# <<< conda initialize <<<'
		;;
	pathreset)
		echo '# rc that rebuilds PATH from scratch (common in dotfiles)'
		echo "export PATH=\"\$HOME/bin:$BASE_PATH\""
		;;
	hostmise | hostmiseaggr)
		echo "eval \"\$(\"\$HOME/.local/bin/mise\" activate $2)\""
		;;
	esac
}

setup_scenarios() {
	for _sc in $SCENARIOS; do
		_h="$DEST/homes/$_sc"
		rm -rf "$_h"
		mkdir -p "$_h/.config/git" "$_h/.config/lazygit"
		printf '[user]\n\tname = %s\n' "$GIT_FIXTURE_NAME" >"$_h/.config/git/config"
		: >"$_h/.config/lazygit/config.yml"
		rc_body "$_sc" bash >"$_h/.bashrc"
		rc_body "$_sc" zsh >"$_h/.zshrc"
		case "$_sc" in
		conda)
			fake_bin "$_h/miniconda3/bin" rg fake-rg-conda
			fake_bin "$_h/miniconda3/bin" nvim fake-nvim-conda
			fake_bin "$_h/miniconda3/bin" python fake-python-conda
			;;
		pathreset) fake_bin "$_h/bin" rg fake-rg-home-bin ;;
		hostmise | hostmiseaggr)
			mkdir -p "$_h/.local/bin" "$_h/.config/mise"
			cp "$DITTO_MISE_BIN" "$_h/.local/bin/mise"
			fake_bin "$_h/hostmise-bin" rg fake-rg-host-mise
			cat >"$_h/.config/mise/config.toml" <<-'EOF'
				[env]
				HOST_MISE_MARKER = "host"
				_.path = ["{{env.HOME}}/hostmise-bin"]
			EOF
			# activate_aggressive: hook-env pushes its paths to the front of
			# PATH at every prompt, ahead of anything set after activation.
			if [ "$_sc" = hostmiseaggr ]; then
				printf '[settings]\nactivate_aggressive = true\n' >>"$_h/.config/mise/config.toml"
			fi
			;;
		esac
	done
	# A workspace mise.toml (the user's own, not ditto's): A must not load it.
	printf '[env]\nWS_MARKER = "workspace-config-leaked"\n' >"$DEST/mise.toml"
	# Commands sourced inside each session.
	cat >"$DEST/check.sh" <<-EOF
		echo "@@PATH0=\${PATH%%:*}"
		echo "@@RG=\$(command -v rg)"
		echo "@@RC=\${DITTO_SPIKE_RC_LOADED-}"
		env | sed -n 's/^\(_*MISE_[A-Za-z0-9_]*\)=.*/@@MISEVAR \1/p'
		env | grep -E '^(XDG_|DITTO_|HOST_MISE_|WS_MARKER|CONDA_PREFIX|GIT_CONFIG_GLOBAL|LG_CONFIG_FILE|RIPGREP_CONFIG_PATH)' | sed 's/^/@@VAR /' | sort
		if [ -x "\$HOME/.local/bin/mise" ]; then
		  "\$HOME/.local/bin/mise" config ls 2>&1 | sed 's/^/@@HMCFG /'
		  "\$HOME/.local/bin/mise" doctor 2>/dev/null | sed -n 's/^  data: /@@HMDATA /p'
		fi
		if [ -n "\${SPIKE_NVIM_OUT-}" ] && [ -x "$D/bin/nvim" ]; then
		  export SPIKE_SSH_FIXTURE=${DITTO_SPIKE_SSH_FIXTURE:-0}
		  nvim --headless -c "luafile $HERE/nvim-check.lua" -c 'qa!' >/dev/null 2>&1 </dev/null
		  sed 's/^/@@NVIM /' "\$SPIKE_NVIM_OUT"
		fi
	EOF
}

# run_case <scenario> <shell> <launcher> — runs the session non-interactively
# but with an interactive shell (-i): the user's rc is loaded and the prompt
# hooks (PROMPT_COMMAND / precmd) run before every line read.
run_case() {
	_sc=$1 _sh=$2 _l=$3
	_h="$DEST/homes/$_sc"
	_out="$LOGS/sess-$_sc-$(basename "$_sh")-$_l.txt"
	_nvo=""
	case "$_l" in up-a | up-a-rc | up-b) _nvo="$LOGS/nvim-$_sc-$(basename "$_sh")-$_l.txt" ;; esac
	_pre=""
	case "$_l" in
	env-a | env-b) _pre="eval \"\$(sh '$HERE/session.sh' '$D' $_l '$_sh')\"" ;;
	esac
	{
		[ -n "$_pre" ] && echo "$_pre"
		echo ':'
		echo ':'
		echo "export SPIKE_NVIM_OUT='$_nvo'; . '$DEST/check.sh'"
		echo 'exit'
	} >"$LOGS/input-$_sc-$_l.txt"
	# Outer shell = the user's interactive shell where `ditto` is typed.
	case "$_l" in
	base | env-a | env-b) _cmd="" ;;
	*) _cmd="exec sh '$HERE/session.sh' '$D' $_l '$_sh'" ;;
	esac
	(
		cd "$DEST" || exit 1
		if [ -n "$_cmd" ]; then
			env -i HOME="$_h" SHELL="$_sh" PATH="$BASE_PATH" TERM=dumb LANG=C \
				"$_sh" -i -c "$_cmd" <"$LOGS/input-$_sc-$_l.txt"
		else
			env -i HOME="$_h" SHELL="$_sh" PATH="$BASE_PATH" TERM=dumb LANG=C \
				"$_sh" -i <"$LOGS/input-$_sc-$_l.txt"
		fi
	) >"$_out" 2>"$_out.stderr"
	return 0
}

field() { sed -n "s/^@@$2=//p" "$1" | head -n 1; }
misevars() { sed -n 's/^@@MISEVAR //p' "$1" | sort -u; }
vars() { sed -n "s/^@@VAR \($2[A-Za-z0-9_]*\)=.*/\1/p" "$1" | sort -u; }
nv() { sed -n "s/^@@NVIM $2=//p" "$1" | head -n 1; }

eval_case() {
	_sc=$1 _sh=$2 _l=$3
	_s=$(basename "$_sh")
	_o="$LOGS/sess-$_sc-$_s-$_l.txt"
	_b="$LOGS/sess-$_sc-$_s-base.txt"
	_t="$_l/$_sc/$_s"
	if [ ! -s "$_o" ]; then
		result "T3-start" FAIL "$_t: no output ($(head -n 3 "$_o.stderr" | tr '\n' ' '))"
		return 0
	fi
	check "T4-path-first" "$D/bin" "$(field "$_o" PATH0)" "$_t"
	check "T4-rg" "$D/bin/rg" "$(field "$_o" RG)" "$_t"
	check "T3-rc-loaded" 1 "$(field "$_o" RC)" "$_t"
	_act=$(sed -n 's/^@@VAR DITTO_ACTIVE=//p' "$_o")
	_root=$(sed -n 's/^@@VAR DITTO_ROOT=//p' "$_o")
	check "T3-ditto-vars" "1 $D" "$_act $_root" "$_t"
	_new=$(misevars "$_o" | comm -13 "$(misevars "$_b" >"$LOGS/.b" && echo "$LOGS/.b")" - | tr '\n' ' ')
	if [ -z "$_new" ]; then
		result T5-no-mise-vars PASS "$_t: no MISE_*/__MISE_* beyond the host's"
	else
		result T5-no-mise-vars FAIL "$_t: new in the subshell: $_new"
	fi
	_newx=$(vars "$_o" XDG_ | comm -13 "$(vars "$_b" XDG_ >"$LOGS/.b" && echo "$LOGS/.b")" - | tr '\n' ' ')
	if [ -z "$_newx" ]; then
		result T5-no-xdg PASS "$_t: no XDG_* exported in the subshell"
	else
		result T5-no-xdg FAIL "$_t: $_newx"
	fi
	_ws=$(grep -c '^@@VAR WS_MARKER' "$_o")
	_wsb=$(grep -c '^@@VAR WS_MARKER' "$_b")
	check T4-ws-config "$_wsb" "$_ws" "$_t: <ws>/mise.toml [env] loaded as without ditto"
	case "$_sc" in hostmise*)
		check T4-host-mise-config "$(sed -n 's/^@@HMCFG //p' "$_b" | tr '\n' ' ')" "$(sed -n 's/^@@HMCFG //p' "$_o" | tr '\n' ' ')" "$_t: host mise config ls"
		check T4-host-mise-data "$(sed -n 's/^@@HMDATA //p' "$_b")" "$(sed -n 's/^@@HMDATA //p' "$_o")" "$_t: host mise data dir"
		check T4-host-mise-env "$(grep -c '^@@VAR HOST_MISE_MARKER=host' "$_b")" "$(grep -c '^@@VAR HOST_MISE_MARKER=host' "$_o")" "$_t: host mise [env] still applied"
		;;
	esac
	if grep -q '^@@NVIM ' "$_o"; then
		check T5-nvim-xdg "$D/config" "$(nv "$_o" nvim_xdg_config)" "$_t: XDG_CONFIG_HOME inside nvim"
		check T5-nvim-shell "$D/bin/.host-sh" "$(nv "$_o" nvim_shell)" "$_t"
		check T5-bang-xdg "" "$(nv "$_o" bang_xdg)" "$_t: XDG_* seen by :!"
		check T5-bang-git "$GIT_FIXTURE_NAME" "$(nv "$_o" bang_git)" "$_t: git from :!"
		check T5-list-git "$GIT_FIXTURE_NAME" "$(nv "$_o" list_git)" "$_t: git run by nvim with argv (gitsigns)"
		result T5-list-git-control INFO "$_t: $(nv "$_o" git_version); without GIT_CONFIG_GLOBAL git sees '$(nv "$_o" list_git_without_gcg)'"
		check T5-list-git-include "$GIT_FIXTURE_NAME" "$(nv "$_o" list_git_include)" "$_t: alternative [include] in nvim's XDG git/config"
		check T5-term-xdg "" "$(nv "$_o" term_xdg)" "$_t: XDG_* in :terminal"
		check T5-term-git "$GIT_FIXTURE_NAME" "$(nv "$_o" term_git)" "$_t: git in :terminal"
		check T5-lazygit-path "$D/bin/lazygit" "$(nv "$_o" lazygit_path)" "$_t: lazygit resolved by nvim"
		case "$(nv "$_o" lazygit_cd)" in
		"$D"/config*) result T5-lazygit-xdg FAIL "$_t: lazygit -cd = $(nv "$_o" lazygit_cd)" ;;
		*) result T5-lazygit-xdg PASS "$_t: lazygit -cd = $(nv "$_o" lazygit_cd | sed "s#$DEST#<dest>#")" ;;
		esac
		check T5-lazygit-env-xdg "" "$(nv "$_o" wrapped_xdg)" "$_t: XDG_* seen by lazygit and its git"
		check T5-lazygit-git "$GIT_FIXTURE_NAME" "$(nv "$_o" wrapped_git)" "$_t: git under lazygit"
		check T5-lazygit-gcg unset "$(nv "$_o" wrapped_gcg)" "$_t: GIT_CONFIG_GLOBAL restored"
		if [ "${DITTO_SPIKE_SSH_FIXTURE:-0}" = 1 ]; then
			for _k in bang_ssh term_ssh wrapped_ssh; do
				check "T5-ssh-${_k%_ssh}" "user $SSH_FIXTURE_USER" "$(nv "$_o" "$_k")" "$_t: ssh -G (~/.ssh/config of the passwd home)"
			done
		fi
	fi
}

t3_sessions() {
	_shells=""
	for _s in ${DITTO_SPIKE_SHELLS:-bash zsh}; do
		_p=$(command -v "$_s" 2>/dev/null) && _shells="$_shells $_p"
	done
	[ -n "$_shells" ] || { result T3-shells FAIL "neither bash nor zsh"; return 0; }
	result T3-shells INFO "$_shells ($(for _s in $_shells; do "$_s" --version 2>/dev/null | head -n 1; done | tr '\n' ';'))"
	for _sc in $SCENARIOS; do
		for _sh in $_shells; do
			_ls="base up-a up-a-rc up-b env-a env-b"
			[ "$_sc" = clean ] && _ls="$_ls up-a-raw"
			for _l in $_ls; do
				run_case "$_sc" "$_sh" "$_l"
			done
			for _l in $_ls; do
				[ "$_l" = base ] || eval_case "$_sc" "$_sh" "$_l"
			done
		done
	done
}

# `mise exec` (ditto run) and `mise env` (ditto env): what a child sees.
t3_exec_env() {
	for _m in run-a-raw run-a run-b; do
		_e=$(cd "$DEST" && env -i HOME="$DEST/homes/clean" PATH="$BASE_PATH" sh "$HERE/session.sh" "$D" "$_m" -- env)
		_names=$(echo "$_e" | sed -n 's/^\(_*MISE_[A-Za-z0-9_]*\)=.*/\1/p' | sort -u | tr '\n' ' ')
		_n=$(echo "$_names" | wc -w | tr -d ' ')
		_p0=$(echo "$_e" | sed -n 's/^PATH=//p' | cut -d: -f1)
		_ws=$(echo "$_e" | grep -c '^WS_MARKER=')
		if [ "$_n" = 0 ]; then
			result T3-exec-child PASS "$_m: 0 MISE_* in the child; PATH[0]=$_p0; ws config=$_ws"
		else
			result T3-exec-child FAIL "$_m: $_n MISE_* in the child ($(echo "$_names" | cut -c1-160)…); PATH[0]=$_p0; ws config=$_ws"
		fi
	done
	_ea=$(cd "$DEST" && env -i HOME="$DEST/homes/clean" PATH="$BASE_PATH" sh "$HERE/session.sh" "$D" env-a bash)
	echo "$_ea" >"$LOGS/env-a.txt"
	result T3-env-a INFO "mise env -s bash: $(echo "$_ea" | grep -c '^export') export, $(echo "$_ea" | grep -c '^unset') unset lines; __MISE_* in output: $(echo "$_ea" | grep -c '__MISE')"
}

# --------------------------------------------------------------------------
# T6 — overlap table: does the pinned mise have each feature?
# --------------------------------------------------------------------------
t6_overlap() {
	for _c in "en" "exec" "env" "generate install-script" "generate tool-stub" "doctor" "prune" "link" "lock" "set"; do
		# shellcheck disable=SC2086
		if ditto_mise $_c --help >/dev/null 2>&1; then
			result T6-cmd PASS "mise $_c exists"
		else
			result T6-cmd FAIL "mise $_c missing"
		fi
	done
	# [env] directives: _.file (dotenv) and _.path, through `mise env`.
	mkdir -p "$D/overlap"
	printf 'SPIKE_FROM_FILE=ok\n' >"$D/overlap/x.env"
	printf '[env]\n_.file = "%s/overlap/x.env"\n_.path = ["%s/overlap/bin"]\n' "$D" "$D" >"$D/overlap/mise.toml"
	_o=$( (
		_ditto_mise_isolate
		export MISE_GLOBAL_CONFIG_FILE="$D/overlap/mise.toml" MISE_TRUSTED_CONFIG_PATHS="$D/overlap"
		cd "$D/mise" && exec "$DITTO_MISE_BIN" env -s bash
	) 2>&1)
	if echo "$_o" | grep -q 'SPIKE_FROM_FILE=ok' && echo "$_o" | grep -q "$D/overlap/bin"; then
		result T6-env-directives PASS "_.file and _.path applied by mise env"
	else
		result T6-env-directives FAIL "$(echo "$_o" | head -n 3 | tr '\n' ' ')"
	fi
	# tool-stub: what a generated stub looks like (no download).
	if ditto_mise generate tool-stub "$D/overlap/stub-rg" --url "https://example.invalid/rg.tar.gz" --skip-download >"$LOGS/tool-stub.txt" 2>&1; then
		cp "$D/overlap/stub-rg" "$LOGS/tool-stub-rg.txt"
		result T6-tool-stub INFO "shebang: $(head -n 1 "$D/overlap/stub-rg"); keys: $(grep -oE '^[a-z_]+ *=' "$D/overlap/stub-rg" | tr -d ' =' | tr '\n' ' ')"
	else
		result T6-tool-stub INFO "generate tool-stub failed: $(tail -n 2 "$LOGS/tool-stub.txt" | tr '\n' ' ')"
	fi
}

# --------------------------------------------------------------------------
MARKER="$LOGS/marker"
: >"$MARKER"
sleep 1
result T0-host INFO "$(uname -sm) libc=$(ditto_libc) mise=$DITTO_MISE_VERSION"

: >"$LOGS/outside-t1.txt"
if t1_bootstrap; then
	outside_since "$MARKER" >"$LOGS/outside-t1.txt"
	if [ -s "$LOGS/outside-t1.txt" ]; then
		result T1-install-script-outside INFO "left outside .ditto: $(head -n 3 "$LOGS/outside-t1.txt" | tr '\n' ' ')"
	else
		result T1-install-script-outside PASS "nothing left outside .ditto"
	fi
	# macOS mktemp -d ignores TMPDIR and uses the per-user temp dir
	# (/var/folders/…/T), which the watch above does not cover (too noisy).
	if [ "$(uname -s)" = Darwin ] && _ut=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null) && [ -n "$_ut" ]; then
		find "$_ut" -maxdepth 2 -newer "$MARKER" -name 'mise-v*' 2>/dev/null >"$LOGS/outside-t1-darwin.txt" || true
		if [ -s "$LOGS/outside-t1-darwin.txt" ]; then
			result T1-install-script-darwin-tmp INFO "mktemp -d ignores TMPDIR on macOS; left in DARWIN_USER_TEMP_DIR: $(sed 's#.*/T/#<DARWIN_USER_TEMP_DIR>/#' "$LOGS/outside-t1-darwin.txt" | tr '\n' ' ')"
		else
			result T1-install-script-darwin-tmp PASS "nothing left in DARWIN_USER_TEMP_DIR"
		fi
	fi
fi
if [ -n "${D:-}" ] && t2_prepare; then
	setup_scenarios
	t3_sessions
	t3_exec_env
	t6_overlap
fi

_out="$LOGS/outside.txt"
outside_since "$MARKER" >"$_out"
# Known writes reported on their own: the install-script's mktemp dir
# (T1-install-script-outside) and nvim's tempdir ($TMPDIR or /tmp/nvim.<user>,
# out of scope here: H0.4).
grep -E '/nvim\.[^/]+(/|$)' "$_out" >"$LOGS/outside-nvim.txt" || true
if [ -s "$LOGS/outside-nvim.txt" ]; then
	result T7-nvim-tmp INFO "nvim tempdir outside .ditto (H0.4): $(head -n 3 "$LOGS/outside-nvim.txt" | tr '\n' ' ')"
fi
grep -v -E '/nvim\.[^/]+(/|$)' "$_out" | grep -v -F -x -f "$LOGS/outside-t1.txt" >"$_out.rest" || true
mv "$_out.rest" "$_out"
if [ -s "$_out" ]; then
	result T7-outside FAIL "$(wc -l <"$_out" | tr -d ' ') path(s) outside <dest>: $(head -n 5 "$_out" | tr '\n' ' ')"
else
	result T7-outside PASS "nothing written in $(watch_dirs | tr '\n' ' ')"
fi

echo "SUMMARY fails=$FAILS pass=$(grep -c ' PASS ' "$RESULTS") logs=$LOGS"
[ "$FAILS" = 0 ]
