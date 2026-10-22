#!/bin/sh
# Spike H0.1b — stand-in for `ditto up` / `ditto env` / `ditto run`, in both
# designs. Expects .ditto/ already prepared by run.sh (mise, wrappers,
# session config and rc files).
#
#   sh session.sh <ditto_dir> up-a|up-a-raw|up-a-rc|up-b [shell]   # subshell
#   sh session.sh <ditto_dir> env-a|env-b [bash|zsh]       # for eval
#   sh session.sh <ditto_dir> run-a|run-a-raw|run-b -- <cmd...>
#
# up-a     mise en -s "<shell> -i" <cwd>, session config "clean"
# up-a-raw the same with the minimal session config of the issue
# up-a-rc  mise en, but the shell started with ditto's rcfile/ZDOTDIR (hybrid)
# up-b     ditto's own rcfile/ZDOTDIR (arch.md §12)
set -u
SPIKE_H01B_DIR=$(cd "$(dirname "$0")" && pwd -P)
. "$SPIKE_H01B_DIR/lib.sh"

[ $# -ge 2 ] || { echo "usage: $0 <ditto_dir> <mode> [args]" >&2; exit 2; }
ditto_mise_paths "$1"
mode=$2
shift 2
sh_=${1:-${SHELL:-/bin/sh}}

case "$mode" in
up-a) spike_mise_session clean en -s "$sh_ -i" "$PWD" ;;
up-a-raw) spike_mise_session raw en -s "$sh_ -i" "$PWD" ;;
up-a-rc)
	# Hybrid: mise en, but the shell loads ditto's B rc files (user rc first,
	# then .ditto/bin first + prompt hook).
	case "$(basename "$sh_")" in
	bash) spike_mise_session clean en -s "$sh_ --rcfile $DITTO_DIR/session/bashrc -i" "$PWD" ;;
	zsh)
		export DITTO_ORIG_ZDOTDIR="${ZDOTDIR-}" ZDOTDIR="$DITTO_DIR/session/zsh"
		spike_mise_session clean en -s "$sh_ -i" "$PWD"
		;;
	esac
	;;
up-b)
	_d=$DITTO_DIR
	unset DITTO_DIR DITTO_MISE_BIN DITTO_MISE_CONFIG DITTO_MISE_LOCK DITTO_REAL_HOME
	spike_launch_b "$_d" "$sh_"
	;;
env-a) spike_mise_session clean env -s "$(basename "$sh_")" ;;
env-b) spike_env_b "$DITTO_DIR" ;;
run-a | run-a-raw)
	[ "${1:-}" = -- ] && shift
	_m=clean
	[ "$mode" = run-a-raw ] && _m=raw
	spike_mise_session "$_m" exec -- "$@"
	;;
run-b)
	[ "${1:-}" = -- ] && shift
	_d=$DITTO_DIR
	unset DITTO_DIR DITTO_MISE_BIN DITTO_MISE_CONFIG DITTO_MISE_LOCK DITTO_REAL_HOME
	DITTO_ACTIVE=1 DITTO_ROOT=$_d PATH="$_d/bin:$PATH" exec "$@"
	;;
*) echo "unknown mode: $mode" >&2; exit 2 ;;
esac
