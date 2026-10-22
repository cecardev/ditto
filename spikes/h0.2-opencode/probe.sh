#!/bin/sh
# probe.sh <opencode-bin> <out-dir> <spike-dir>
#
# Runs OpenCode without credentials in three scenarios, each with a fresh
# fake HOME and a fake system TMPDIR, and lists every file written:
#   none       no isolation variables (OpenCode defaults)
#   configdir  only OPENCODE_CONFIG_DIR (what arch.md §8 had so far)
#   wrapper    the wrapper.sh prototype (XDG_* only inside the wrapper)
set -u

OC=$1
OUT=$2
SPIKE=$3
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
# Marker on the container's own filesystem (bind mounts have host mtimes).
START=/tmp/.h02-spike-start
if [ -f /.dockerenv ]; then
	: >"$START"
	sleep 1
fi

# run_t <secs> <cmd...>: portable timeout (macOS has no timeout(1)).
# SIGTERM, then SIGKILL 5s later (a stuck Bun process may ignore SIGTERM).
run_t() {
	secs=$1
	shift
	"$@" &
	pid=$!
	(sleep "$secs" && kill "$pid" 2>/dev/null && sleep 5 && kill -9 "$pid" 2>/dev/null) &
	watcher=$!
	wait "$pid"
	rc=$?
	kill "$watcher" 2>/dev/null
	wait "$watcher" 2>/dev/null
	return $rc
}

echo "## platform"
echo "uname: $(uname -s) $(uname -m)"
if [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	echo "os: $PRETTY_NAME"
fi
if command -v ldd >/dev/null 2>&1; then
	echo "libc: $(ldd --version 2>&1 | head -1)"
fi
if [ -r /proc/cpuinfo ]; then
	if grep -qw avx2 /proc/cpuinfo; then echo "avx2: yes (cpuinfo)"; else echo "avx2: no (cpuinfo)"; fi
elif command -v sysctl >/dev/null 2>&1; then
	echo "cpu: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
fi
# Even `--version` creates the XDG dirs and $TMPDIR/opencode (mkdir at
# import), so it also runs inside a throwaway HOME/TMPDIR.
mkdir -p "$OUT/version/home" "$OUT/version/tmp"
echo "version: $(env -i PATH="$PATH" HOME="$OUT/version/home" TMPDIR="$OUT/version/tmp" "$OC" --version 2>&1 | tail -1)"
echo "dirs created by --version alone:"
(cd "$OUT/version" && find . -mindepth 1 -maxdepth 4 -type d | sort)

scenario() {
	name=$1
	S="$OUT/$name"
	H="$S/home"
	T="$S/systmp"
	R="$S/ws/.ditto"
	P="$S/ws/proj"
	mkdir -p "$H" "$T" "$R" "$P"
	cat >"$P/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "envdump": {
      "type": "local",
      "command": ["sh", "$SPIKE/envdump.sh", "$S/mcp-env.txt"],
      "enabled": true
    }
  }
}
EOF
	case $name in
	none) set -- "$OC" ;;
	configdir) set -- env OPENCODE_CONFIG_DIR="$R/config/opencode" "$OC" ;;
	wrapper)
		# ditto creates .ditto/tmp during `up`: the x64 builds abort when
		# TMPDIR does not exist (see tmpdir-check.sh).
		mkdir -p "$R/tmp"
		set -- env DITTO_ROOT="$R" DITTO_OPENCODE_BIN="$OC" sh "$SPIKE/wrapper.sh"
		;;
	esac
	log="$S/commands.log"
	# shellcheck disable=SC2129 # one append per command keeps the log ordered
	(
		cd "$P" || exit 1
		base="env -i PATH=$PATH HOME=$H TMPDIR=$T TERM=dumb LANG=C.UTF-8 SHELL=/bin/sh"
		for sub in "debug paths" "mcp list" "session list" "models"; do
			echo "\$ opencode $sub" >>"$log"
			# shellcheck disable=SC2086 # word splitting of $base/$sub is intended
			run_t 120 $base "$@" $sub >>"$log" 2>&1
			echo "exit=$?" >>"$log"
		done
		echo "\$ opencode serve --port 0 (8s)" >>"$log"
		# shellcheck disable=SC2086
		run_t 8 $base "$@" serve --port 0 --hostname 127.0.0.1 >>"$log" 2>&1
		echo "exit=$? (killed after 8s is expected)" >>"$log"
	)
	echo
	echo "## scenario: $name"
	echo "### debug paths"
	sed -n '/^\$ opencode debug paths/,/^exit=/p' "$log" | sed "s|$S|<S>|g"
	echo "### exits"
	grep -E '^(\$|exit=)' "$log" | paste - - | sed "s|$S|<S>|g"
	echo "### files written in fake HOME (escapes)"
	(cd "$H" && find . -mindepth 1 -maxdepth 4 | sort) || true
	echo "### files written in fake system TMPDIR (escapes)"
	(cd "$T" && find . -mindepth 1 -maxdepth 3 | sort) || true
	echo "### files written in workspace .ditto/"
	(cd "$R" && find . -mindepth 1 -maxdepth 4 | sort) || true
	echo "### files written in project dir (besides opencode.json)"
	(cd "$P" && find . -mindepth 1 -maxdepth 3 ! -name opencode.json | sort) || true
	echo "### env seen by child process (local MCP)"
	if [ -f "$S/mcp-env.txt" ]; then sed "s|$S|<S>|g" "$S/mcp-env.txt"; else echo "(MCP not started)"; fi
}

for s in none configdir wrapper; do
	scenario "$s"
done

if [ -f /.dockerenv ]; then
	echo
	echo "## files written anywhere else in the container (outside $OUT)"
	find / -xdev \( -path /proc -o -path /sys -o -path /dev -o -path "$OUT" -o -path /spike -o -path /oc \) -prune -o \
		-newer "$START" ! -path "$START" -print 2>/dev/null | sort | head -50
fi
