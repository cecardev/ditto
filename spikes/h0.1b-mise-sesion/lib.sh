# shellcheck shell=sh
# Spike H0.1b — session helpers on top of spikes/h0.1-mise-aislado/env.sh.
#
#   . spikes/h0.1b-mise-sesion/lib.sh   # also sources ../h0.1-mise-aislado/env.sh
#
# Two ways of opening the ditto session are prototyped side by side:
#
#   A  delegated to mise: a session-only mise config ([env] + _.path, no
#      [tools]) and `mise en` / `mise exec` / `mise env`.
#   B  ditto's own session: bash --rcfile / zsh ZDOTDIR that load the user's
#      rc first and then put .ditto/bin first (plus a prompt hook).
#
# Both share the per-tool wrappers in .ditto/bin (written as sh, the way Go
# would generate them). env.sh is reused unchanged; the only addition is
# spike_mise_session, a copy of ditto_mise that swaps the global config for
# the session config and keeps the real HOME (see RESULTS.md).
#
# Throwaway spike code: the production version lives in internal/env and
# internal/launcher.

# The caller sets SPIKE_H01B_DIR (this directory); env.sh is its sibling.
: "${SPIKE_H01B_DIR:?set SPIKE_H01B_DIR to spikes/h0.1b-mise-sesion}"
# shellcheck source=../h0.1-mise-aislado/env.sh
. "$SPIKE_H01B_DIR/../h0.1-mise-aislado/env.sh"

# Variables that the nvim wrapper overrides and every other wrapper (and
# .host-sh) restores. GIT_CONFIG_GLOBAL is set by the nvim wrapper when the
# user's git config lives in $XDG_CONFIG_HOME/git/config (arch.md §8).
SPIKE_SAVED_VARS="XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME GIT_CONFIG_GLOBAL"

# _spike_restore_block — sh code that restores the DITTO_ORIG_* saved by the
# nvim wrapper (unset if the variable was unset), unrolled per variable so
# the generated wrappers need no eval.
_spike_restore_block() {
	echo 'if [ "${DITTO_IN_NVIM-}" = 1 ]; then'
	for _v in $SPIKE_SAVED_VARS; do
		printf '\tif [ "${DITTO_ORIG_SET_%s-}" = 1 ]; then export %s="${DITTO_ORIG_%s-}"; else unset %s; fi\n' "$_v" "$_v" "$_v" "$_v"
		printf '\tunset DITTO_ORIG_SET_%s DITTO_ORIG_%s\n' "$_v" "$_v"
	done
	echo '	PATH=$DITTO_ORIG_PATH; export PATH'
	echo '	unset DITTO_ORIG_PATH DITTO_IN_NVIM'
	echo 'fi'
}

# spike_write_wrappers <ditto_dir> <nvim> <lazygit> <rg> — writes
# .ditto/bin/{nvim,lazygit,rg,.host-sh,.probe} and the minimal nvim config.
# Arguments are absolute paths (from `mise which`); empty skips that wrapper.
# .probe is not a product wrapper: it runs "$@" after the same restore block
# every wrapper has, so a test can see what lazygit (and the git it spawns)
# receives.
spike_write_wrappers() {
	_d=$1
	mkdir -p "$_d/bin" "$_d/config/nvim" "$_d/data" "$_d/state" "$_d/cache" "$_d/lazygit" "$_d/ripgrep"
	if [ -n "$2" ]; then
		{
			echo '#!/bin/sh'
			echo '# ditto wrapper: nvim (XDG_* only here, arch.md §8)'
			_spike_restore_block
			for _v in $SPIKE_SAVED_VARS; do
				printf 'if [ -n "${%s+x}" ]; then export DITTO_ORIG_SET_%s=1 DITTO_ORIG_%s="$%s"; fi\n' "$_v" "$_v" "$_v" "$_v"
			done
			echo 'export DITTO_ORIG_PATH="$PATH" DITTO_IN_NVIM=1'
			echo '_git_xdg="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"'
			echo 'if [ -z "${GIT_CONFIG_GLOBAL+x}" ] && [ -f "$_git_xdg" ]; then export GIT_CONFIG_GLOBAL="$_git_xdg"; fi'
			echo 'unset _git_xdg'
			printf 'export XDG_CONFIG_HOME="%s/config" XDG_DATA_HOME="%s/data" XDG_STATE_HOME="%s/state" XDG_CACHE_HOME="%s/cache"\n' "$_d" "$_d" "$_d" "$_d"
			printf 'exec "%s" "$@"\n' "$2"
		} >"$_d/bin/nvim"
		printf 'vim.o.shell = "%s/bin/.host-sh"\n' "$_d" >"$_d/config/nvim/init.lua"
	fi
	if [ -n "$3" ]; then
		{
			echo '#!/bin/sh'
			echo '# ditto wrapper: lazygit (LG_CONFIG_FILE, arch.md §8)'
			_spike_restore_block
			printf 'export LG_CONFIG_FILE="%s/lazygit/config.yml"\n' "$_d"
			printf 'exec "%s" "$@"\n' "$3"
		} >"$_d/bin/lazygit"
		: >"$_d/lazygit/config.yml"
	fi
	if [ -n "$4" ]; then
		{
			echo '#!/bin/sh'
			echo '# ditto wrapper: rg (RIPGREP_CONFIG_PATH, arch.md §8)'
			_spike_restore_block
			printf 'export RIPGREP_CONFIG_PATH="%s/ripgrep/config"\n' "$_d"
			printf 'exec "%s" "$@"\n' "$4"
		} >"$_d/bin/rg"
		: >"$_d/ripgrep/config"
	fi
	{
		echo '#!/bin/sh'
		echo "# ditto: shell for nvim's :terminal / :! (vim.o.shell), restores the host env"
		_spike_restore_block
		echo 'exec "${SHELL:-/bin/sh}" "$@"'
	} >"$_d/bin/.host-sh"
	{
		echo '#!/bin/sh'
		echo '# spike only: the restore block of every wrapper, then "$@"'
		_spike_restore_block
		echo 'exec "$@"'
	} >"$_d/bin/.probe"
	chmod 0755 "$_d"/bin/* "$_d/bin/.host-sh" "$_d/bin/.probe"
}

# --------------------------------------------------------------------------
# Option A: session delegated to mise.
# --------------------------------------------------------------------------

# spike_write_session_toml <ditto_dir> <raw|clean> — the session-only mise
# config. "raw" is the minimal [env] of the issue. "clean" also unsets (VAR =
# false) every MISE_* the isolation sets, so `mise en`/`exec` children do not
# inherit them. There is no [tools]: tool bin dirs would otherwise land on
# PATH next to the wrappers (runtimes visible in the subshell, arch.md §8).
spike_write_session_toml() {
	mkdir -p "$1/session"
	{
		echo '# Generated by spikes/h0.1b-mise-sesion (option A session config).'
		echo '[env]'
		echo 'DITTO_ACTIVE = "1"'
		echo "DITTO_ROOT = \"$1\""
		echo "_.path = [\"$1/bin\"]"
		if [ "$2" = clean ]; then
			{
				(_ditto_mise_isolate && env) | sed -n 's/^\(MISE_[A-Za-z0-9_]*\)=.*/\1/p'
				printf '%s\n' MISE_GLOBAL_CONFIG_FILE MISE_OVERRIDE_CONFIG_FILENAMES MISE_OVERRIDE_TOOL_VERSIONS_FILENAMES
			} | sort -u | sed 's/$/ = false/'
		fi
	} >"$1/session/mise-$2.toml"
}

# spike_mise_session <raw|clean> <mise args...> — like ditto_mise (env.sh),
# but: the global config is the session config; the real HOME/XDG/TMPDIR are
# kept (the child shell is the user's: a redirected HOME would break it);
# and, for "clean", project config discovery is switched off with
# MISE_OVERRIDE_*_FILENAMES (MISE_CEILING_PATHS does not stop `mise en <ws>`
# from loading <ws>/mise.toml). The spike's own DITTO_* helpers are dropped,
# as the Go binary would not export them.
spike_mise_session() {
	_mode=$1
	shift
	(
		_ditto_mise_isolate
		export MISE_GLOBAL_CONFIG_FILE="$DITTO_DIR/session/mise-$_mode.toml"
		export MISE_TRUSTED_CONFIG_PATHS="$DITTO_DIR/mise:$DITTO_DIR/session"
		if [ "$_mode" = clean ]; then
			export MISE_OVERRIDE_CONFIG_FILENAMES=ditto-none.toml MISE_OVERRIDE_TOOL_VERSIONS_FILENAMES=ditto-none
		fi
		_bin=$DITTO_MISE_BIN
		unset DITTO_DIR DITTO_MISE_BIN DITTO_MISE_CONFIG DITTO_MISE_LOCK DITTO_REAL_HOME
		exec "$_bin" "$@"
	)
}

# --------------------------------------------------------------------------
# Option B: ditto's own session (arch.md §12).
# --------------------------------------------------------------------------

# spike_write_session_rc <ditto_dir> — rc files for bash (--rcfile) and zsh
# (ZDOTDIR). Both load the user's rc first, then put .ditto/bin first and
# register a prompt hook that keeps it first: `mise activate` (or direnv,
# pyenv…) in the user's rc re-prepends its paths at every prompt.
spike_write_session_rc() {
	_d=$1
	mkdir -p "$_d/session/zsh"
	cat >"$_d/session/path.sh" <<-EOF
		# ditto: keep .ditto/bin first in PATH (idempotent).
		__ditto_path() {
		  case "\$PATH" in
		  "$_d/bin" | "$_d/bin":*) return 0 ;;
		  esac
		  PATH=\$(printf '%s\n' "\$PATH" | awk -v d="$_d/bin" 'BEGIN { RS = ":"; ORS = "" } { sub(/\n\$/, ""); if (\$0 != d && \$0 != "") { printf "%s%s", (n++ ? ":" : ""), \$0 } }')
		  PATH="$_d/bin\${PATH:+:\$PATH}"
		  export PATH
		}
		export DITTO_ACTIVE=1 DITTO_ROOT="$_d"
		__ditto_path
	EOF
	cat >"$_d/session/bashrc" <<-EOF
		# ditto session for bash: user's rc first, then ditto.
		[ -f "\$HOME/.bashrc" ] && . "\$HOME/.bashrc"
		. "$_d/session/path.sh"
		PROMPT_COMMAND="\${PROMPT_COMMAND:+\$PROMPT_COMMAND\$'\n'}__ditto_path"
	EOF
	cat >"$_d/session/zsh/.zshenv" <<-EOF
		# ditto session for zsh: ZDOTDIR points here only until the user's
		# files are loaded.
		_ditto_self=\$ZDOTDIR
		_ditto_zd="\${DITTO_ORIG_ZDOTDIR:-\$HOME}"
		[ -f "\$_ditto_zd/.zshenv" ] && . "\$_ditto_zd/.zshenv"
		# A user .zshenv that sets ZDOTDIR would make zsh skip our .zshrc.
		if [ "\$ZDOTDIR" != "\$_ditto_self" ]; then
		  DITTO_ORIG_ZDOTDIR=\$ZDOTDIR _ditto_zd=\$ZDOTDIR
		  ZDOTDIR=\$_ditto_self
		fi
		unset _ditto_self
	EOF
	cat >"$_d/session/zsh/.zshrc" <<-EOF
		if [ -n "\${DITTO_ORIG_ZDOTDIR-}" ]; then ZDOTDIR=\$DITTO_ORIG_ZDOTDIR; else unset ZDOTDIR; fi
		unset DITTO_ORIG_ZDOTDIR
		[ -f "\$_ditto_zd/.zshrc" ] && . "\$_ditto_zd/.zshrc"
		unset _ditto_zd
		. "$_d/session/path.sh"
		precmd_functions+=(__ditto_path)
	EOF
}

# spike_launch_b <ditto_dir> <shell> — opens the B session in <shell>.
spike_launch_b() {
	case "$(basename "$2")" in
	bash) exec "$2" --rcfile "$1/session/bashrc" -i ;;
	zsh) DITTO_ORIG_ZDOTDIR=${ZDOTDIR-} ZDOTDIR="$1/session/zsh" exec "$2" -i ;;
	*) echo "unsupported shell: $2" >&2; return 1 ;;
	esac
}

# spike_env_b <ditto_dir> — what `ditto env` (B) prints for eval.
spike_env_b() {
	printf 'export DITTO_ACTIVE=1 DITTO_ROOT=%s\n' "'$1'"
	printf 'export PATH=%s"${PATH:+:$PATH}"\n' "'$1/bin'"
}
