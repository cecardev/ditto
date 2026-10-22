#!/bin/sh
# Spike H0.1 — validates a pinned, fully isolated mise inside <dest>/.ditto/.
#
#   sh run.sh <dest> [all|online|offline]
#
# <dest> plays the workspace; everything mise does must stay in <dest>/.ditto.
# Phases:
#   online   bootstrap mise (sha256), install from mise.lock, prepare a manual
#            download for `mise link`, host-mise isolation checks.
#   offline  with the network cut by the caller (docker --network none) or by
#            a dead proxy (DITTO_SPIKE_OFFLINE=proxy): `mise link`, `mise
#            where`, reinstall from the lock with zero HTTP requests.
#   all      online, then offline via dead proxy (default; used on macOS).
# Each phase also diffs $HOME, /tmp and $TMPDIR against a marker (test 7).
#
# Environment:
#   DITTO_SPIKE_LOCK=<file>|none   lock to install from (default ./mise.lock)
#   DITTO_SPIKE_HOST_MISE=1        create a fake host mise in $HOME first
#                                  (only with a disposable HOME: docker/macos.sh)
#   DITTO_MISE_FROM=<file>         local copy of the mise binary (still verified)
#   DITTO_SPIKE_WATCH_EXCLUDE=<re> extended regex of paths to ignore in test 7
#                                  (unrelated host noise, e.g. other processes)
#
# Output: "RESULT <id> <PASS|FAIL|INFO|SKIP> <detail>" lines, also stored in
# <dest>/spike-logs/results-<phase>.txt.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
. "$HERE/env.sh"

[ $# -ge 1 ] || { echo "usage: $0 <dest> [all|online|offline]" >&2; exit 2; }
mkdir -p "$1"
DEST=$(cd "$1" && pwd -P)
PHASE=${2:-all}
LOGS="$DEST/spike-logs"
mkdir -p "$LOGS"
LOCK_SRC=${DITTO_SPIKE_LOCK:-$HERE/mise.lock}
FAILS=0

# Test tooling (not ditto prerequisites): without find, test 7 would pass
# vacuously.
for _t in find tar awk sort; do
	command -v "$_t" >/dev/null 2>&1 || { echo "run.sh needs '$_t' on PATH" >&2; exit 2; }
done

result() { # <id> <status> <detail...>
	_id=$1 _st=$2
	shift 2
	echo "RESULT $_id $_st $*" | tee -a "$RESULTS"
	[ "$_st" = FAIL ] && FAILS=$((FAILS + 1))
	return 0
}

# mise platform key used in mise.lock for this host.
host_platform() {
	_p="$(ditto_os)-$(ditto_arch)"
	[ "$(ditto_libc)" = musl ] && _p="$_p-musl"
	echo "$_p"
}

# lock_field <lock> <tool> <platform> <field> — reads checksum/url of the
# first lock entry with that tool and platform.
lock_field() {
	awk -v sec="[tools.\"$2\".\"platforms.$3\"]" -v key="$4" '
		$0 == sec { on = 1; next }
		/^\[/ { on = 0 }
		on && $1 == key { gsub(/"/, "", $3); print $3; exit }
	' "$1"
}

net_reachable() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsS -m 5 -o /dev/null https://github.com 2>/dev/null
	elif command -v wget >/dev/null 2>&1; then
		wget -q -T 5 -t 1 -O /dev/null https://github.com 2>/dev/null
	else
		return 1
	fi
}

# Directories watched for writes outside .ditto (test 7).
watch_dirs() {
	echo "$HOME"
	echo /tmp/
	[ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && echo "$TMPDIR"
	return 0
}

snapshot_start() {
	MARKER="$LOGS/marker-$1"
	: >"$MARKER"
	sleep 1
}

# Files newer than the marker outside <dest> and outside the fake host mise
# (checked by hash in test 8).
snapshot_diff() {
	_out="$LOGS/outside-$1.txt"
	: >"$_out"
	for _d in $(watch_dirs); do
		find "$_d" -newer "$MARKER" 2>/dev/null |
			grep -v -e "^$DEST" -e "^$HOME/.config/mise" -e "^$HOME/.local/share/mise" \
				-e "^$HOME/.local/bin/mise" -e "^$HOME/.local/bin\$" -e "^$HOME/.local/share\$" -e "^$HOME/.local\$" \
				-e "^$HOME/.config\$" -e "^$HOME\$" -e '^/tmp/$' -e "^${TMPDIR:-/nonexistent}\$" |
			grep -v -E "${DITTO_SPIKE_WATCH_EXCLUDE:-^\$}" >>"$_out" || true
	done
	if [ -s "$_out" ]; then
		result "T7-outside-$1" FAIL "$(wc -l <"$_out" | tr -d ' ') path(s) written outside .ditto: $(head -n 5 "$_out" | tr '\n' ' ')"
	else
		result "T7-outside-$1" PASS "nothing written in $(watch_dirs | tr '\n' ' ')"
	fi
}

tree_hash() { # <dir> — stable hash of a tree (names + contents)
	[ -d "$1" ] || { echo absent; return 0; }
	(cd "$1" && find . -type f | LC_ALL=C sort | while read -r _f; do
		printf '%s %s\n' "$_f" "$(ditto_sha256 "$_f")"
	done) | ditto_sha256 -
}

host_mise_setup() {
	# A host mise with its own global config, data dir and a workspace
	# mise.toml in <dest> (parent of .ditto). None of it may leak in.
	mkdir -p "$HOME/.config/mise" "$HOME/.local/share/mise/installs" "$HOME/.local/bin"
	cp "$DITTO_MISE_BIN" "$HOME/.local/bin/mise"
	cat >"$HOME/.config/mise/config.toml" <<-'EOF'
		[tools]
		"aqua:junegunn/fzf" = "0.50.0"
		[env]
		DITTO_SPIKE_HOST_MARKER = "host-global-config-leaked"
		[settings]
		experimental = false
	EOF
	cat >"$DEST/mise.toml" <<-'EOF'
		[tools]
		"aqua:sharkdp/fd" = "9.0.0"
		[env]
		DITTO_SPIKE_WS_MARKER = "workspace-config-leaked"
	EOF
	HOST_CFG_HASH=$(tree_hash "$HOME/.config/mise")
	HOST_DATA_HASH=$(tree_hash "$HOME/.local/share/mise")
}

host_mise_check() { # <isolate-home 0|1>
	_tag="isolate_home=$1"
	_cfg=$(DITTO_MISE_ISOLATE_HOME=$1 ditto_mise config ls 2>&1)
	_env=$(DITTO_MISE_ISOLATE_HOME=$1 ditto_mise env -s bash 2>&1)
	_ls=$(DITTO_MISE_ISOLATE_HOME=$1 ditto_mise ls 2>&1)
	_bad=""
	echo "$_cfg" | grep -q "$HOME/.config/mise" && _bad="$_bad host-config-listed"
	echo "$_cfg" | grep -q "$DEST/mise.toml" && _bad="$_bad workspace-config-listed"
	echo "$_env" | grep -q DITTO_SPIKE_ && _bad="$_bad env-marker-leaked"
	echo "$_ls" | grep -qE '0\.50\.0|9\.0\.0' && _bad="$_bad host-versions-listed"
	if [ -z "$_bad" ]; then
		result T8-host-mise-read PASS "$_tag: isolated mise ignores ~/.config/mise and <ws>/mise.toml"
	else
		result T8-host-mise-read FAIL "$_tag:$_bad"
		printf '%s\n---\n%s\n---\n%s\n' "$_cfg" "$_env" "$_ls" >"$LOGS/t8-$1.txt"
	fi
}

host_mise_verify_untouched() {
	if [ "$(tree_hash "$HOME/.config/mise")" = "$HOST_CFG_HASH" ] &&
		[ "$(tree_hash "$HOME/.local/share/mise")" = "$HOST_DATA_HASH" ]; then
		result T8-host-mise-write PASS "\$HOME/.config/mise and \$HOME/.local/share/mise unchanged"
	else
		result T8-host-mise-write FAIL "host mise dirs changed"
	fi
}

# smoke <name> <cmd...> — runs a binary with HOME/XDG/TMPDIR inside .ditto
# so the tools' own writes (OpenCode, nvim) do not count as mise escaping.
smoke() {
	_n=$1
	shift
	_sh="$DITTO_DIR/smoke-home"
	mkdir -p "$_sh/tmp"
	if _o=$(HOME="$_sh" XDG_CONFIG_HOME="$_sh/.config" XDG_DATA_HOME="$_sh/.local/share" \
		XDG_STATE_HOME="$_sh/.local/state" XDG_CACHE_HOME="$_sh/.cache" TMPDIR="$_sh/tmp" \
		"$@" 2>&1); then
		result "T3-run-$_n" PASS "$(echo "$_o" | head -n 1)"
	else
		result "T3-run-$_n" FAIL "$(echo "$_o" | head -n 2 | tr '\n' ' ')"
	fi
}

smoke_all() {
	for _pair in nvim:--version rg:--version fd:--version fzf:--version \
		lazygit:--version tree-sitter:--version opencode:--version; do
		_bin=${_pair%%:*}
		if [ "$_bin" = nvim ] && [ -z "$(ditto_nvim_tool)" ]; then
			result T3-run-nvim SKIP "no Neovim build for $(ditto_libc); needs source=host/path"
			continue
		fi
		if [ "$_bin" = tree-sitter ] && [ -z "$(ditto_treesitter_tool)" ]; then
			result T3-run-tree-sitter SKIP "no tree-sitter CLI build for $(ditto_libc); needs source=host/path"
			continue
		fi
		if _p=$(ditto_mise which "$_bin" 2>&1); then
			smoke "$_bin" "$_p" "${_pair#*:}"
		else
			result "T3-run-$_bin" FAIL "mise which: $_p"
		fi
	done
}

phase_online() {
	RESULTS="$LOGS/results-online.txt"
	: >"$RESULTS"
	result T0-host INFO "$(uname -sm) libc=$(ditto_libc) platform=$(host_platform) avx2=$(ditto_has_avx2 && echo yes || echo no)"
	snapshot_start online

	ditto_mise_env "$DEST/.ditto"
	if ditto_mise_bootstrap 2>"$LOGS/bootstrap.txt"; then
		result T1-bootstrap PASS "$(ditto_mise_asset) sha256=$(ditto_mise_sha256 "$(ditto_mise_asset)")"
	else
		result T1-bootstrap FAIL "$(cat "$LOGS/bootstrap.txt")"
		return 1
	fi
	_v=$(ditto_mise --version 2>&1 | head -n 1)
	case "$_v" in "$DITTO_MISE_VERSION"*) result T1-version PASS "$_v" ;; *) result T1-version FAIL "$_v" ;; esac

	if [ "${DITTO_SPIKE_HOST_MISE:-0}" = 1 ]; then
		host_mise_setup
	fi

	# Test 2: every mise directory and config file under .ditto/mise.
	ditto_mise doctor >"$LOGS/doctor.txt" 2>&1 || true
	_dirs=$(sed -n '/^dirs:/,/^$/p' "$LOGS/doctor.txt" | grep ': ' | grep -v "$DITTO_DIR/mise" || true)
	if [ -z "$_dirs" ]; then
		result T2-dirs PASS "mise doctor: all dirs under .ditto/mise"
	else
		result T2-dirs FAIL "$_dirs"
	fi

	# Test 3: hand-made config + lock, install.
	ditto_write_config "$MISE_GLOBAL_CONFIG_FILE"
	cp "$MISE_GLOBAL_CONFIG_FILE" "$LOGS/config.toml"
	_cfgls=$(ditto_mise config ls 2>&1)
	if [ "$(echo "$_cfgls" | grep -c .)" = 1 ] && echo "$_cfgls" | grep -q "$MISE_GLOBAL_CONFIG_FILE"; then
		result T2-config PASS "only .ditto/mise/config.toml loaded"
	else
		result T2-config FAIL "$(echo "$_cfgls" | tr '\n' ' ')"
	fi
	_locked=""
	if [ "$LOCK_SRC" != none ]; then
		cp "$LOCK_SRC" "$DITTO_DIR/mise/mise.lock"
		_lock_hash=$(ditto_sha256 "$DITTO_DIR/mise/mise.lock")
		_locked="--locked"
	fi
	# shellcheck disable=SC2086
	if ditto_mise install $_locked >"$LOGS/install.txt" 2>&1; then
		result T3-install PASS "mise install $_locked ($(grep -c '✓' "$LOGS/install.txt" || true) lines ok)"
	else
		result T3-install FAIL "$(tail -n 5 "$LOGS/install.txt" | tr '\n' ' ')"
	fi
	if [ -n "$_locked" ]; then
		if [ "$(ditto_sha256 "$DITTO_DIR/mise/mise.lock")" = "$_lock_hash" ]; then
			result T6-lock-untouched PASS "install --locked did not rewrite mise.lock"
		else
			result T6-lock-untouched INFO "install rewrote mise.lock (diff in spike-logs/lock.diff)"
			diff "$LOCK_SRC" "$DITTO_DIR/mise/mise.lock" >"$LOGS/lock.diff" || true
		fi
	fi
	ditto_mise ls >"$LOGS/ls.txt" 2>&1 || true
	smoke_all

	# Test 4: on legacy glibc also probe the official Neovim build.
	if [ "$(ditto_nvim_tool)" = "github:neovim/neovim-releases" ]; then
		if ditto_mise install "aqua:neovim/neovim@$DITTO_V_NVIM" >"$LOGS/nvim-official.txt" 2>&1; then
			_w=$(ditto_mise where "aqua:neovim/neovim@$DITTO_V_NVIM")
			_nv=$(find "$_w" -type f -name nvim -path '*/bin/*' | head -n 1)
			if _o=$("$_nv" --version 2>&1); then
				result T4-nvim-official INFO "official build runs: $(echo "$_o" | head -n 1)"
			else
				result T4-nvim-official INFO "official build fails as expected: $(echo "$_o" | head -n 1)"
			fi
		else
			result T4-nvim-official INFO "official install failed: $(tail -n 2 "$LOGS/nvim-official.txt" | tr '\n' ' ')"
		fi
	fi

	# Test 5 (prep): manual download of ripgrep, verified against the lock.
	_plat=$(host_platform)
	_url="" _sum=""
	[ "$LOCK_SRC" = none ] || _url=$(lock_field "$LOCK_SRC" github:BurntSushi/ripgrep "$_plat" url)
	[ "$LOCK_SRC" = none ] || _sum=$(lock_field "$LOCK_SRC" github:BurntSushi/ripgrep "$_plat" checksum)
	_dl="$DITTO_DIR/downloads"
	mkdir -p "$_dl/ripgrep"
	if [ "$LOCK_SRC" = none ]; then
		result T5-download SKIP "DITTO_SPIKE_LOCK=none"
	elif [ -n "$_url" ] && _ditto_fetch "$_url" "$_dl/ripgrep.tar.gz"; then
		if [ "sha256:$(ditto_sha256 "$_dl/ripgrep.tar.gz")" = "$_sum" ]; then
			tar -xzf "$_dl/ripgrep.tar.gz" -C "$_dl/ripgrep" --strip-components 1
			result T5-download PASS "$(basename "$_url") sha256 matches mise.lock"
		else
			result T5-download FAIL "sha256 mismatch for $_url"
		fi
	else
		result T5-download FAIL "no url for $_plat in lock or download failed"
	fi

	if [ "${DITTO_SPIKE_HOST_MISE:-0}" = 1 ]; then
		host_mise_check 1
		host_mise_check 0
		host_mise_verify_untouched
	fi
	snapshot_diff online
}

phase_offline() {
	RESULTS="$LOGS/results-offline.txt"
	: >"$RESULTS"
	snapshot_start offline
	ditto_mise_env "$DEST/.ditto"
	if [ "${DITTO_SPIKE_OFFLINE:-}" = proxy ]; then
		# Any HTTP(S) attempt fails fast through a closed local port.
		export HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9
		export https_proxy="$HTTPS_PROXY" http_proxy="$HTTP_PROXY" NO_PROXY="" no_proxy=""
	fi
	if net_reachable; then
		result T6-offline-guard FAIL "network still reachable; offline results are not meaningful"
	else
		result T6-offline-guard PASS "github.com unreachable"
	fi

	# Test 6: everything installed -> no HTTP request at all.
	if [ "$LOCK_SRC" = none ]; then
		result T6-no-network SKIP "DITTO_SPIKE_LOCK=none"
	elif MISE_LOG_HTTP=1 ditto_mise install --locked >"$LOGS/install-offline.txt" 2>&1; then
		_req=$(grep -cE '^(GET|HEAD|POST) |https?://' "$LOGS/install-offline.txt" || true)
		if [ "$_req" = 0 ]; then
			result T6-no-network PASS "install --locked with network cut: 0 HTTP requests"
		else
			result T6-no-network FAIL "$_req HTTP line(s): $(grep -m 3 -E 'https?://' "$LOGS/install-offline.txt" | tr '\n' ' ')"
		fi
	else
		result T6-no-network FAIL "$(tail -n 5 "$LOGS/install-offline.txt" | tr '\n' ' ')"
	fi
	if _w=$(MISE_LOG_HTTP=1 ditto_mise which rg 2>&1); then
		result T6-which-offline PASS "$_w"
	else
		result T6-which-offline FAIL "$_w"
	fi

	# Test 5: mise link of the manual download, no network.
	_dir="$DITTO_DIR/downloads/ripgrep"
	if [ -x "$_dir/rg" ]; then
		if _o=$(MISE_LOG_HTTP=1 ditto_mise link -f "github:BurntSushi/ripgrep@$DITTO_V_RG-path" "$_dir" 2>&1); then
			_where=$(ditto_mise where "github:BurntSushi/ripgrep@$DITTO_V_RG-path" 2>&1)
			_rw=$(cd "$_where" 2>/dev/null && pwd -P)
			if [ "$_rw" = "$_dir" ] && "$_where/rg" --version >/dev/null 2>&1; then
				result T5-link PASS "mise where -> $_where ($("$_where/rg" --version | head -n 1))"
			else
				result T5-link FAIL "where=$_where"
			fi
			echo "$_o" | grep -qE 'https?://' && result T5-link-http FAIL "link made HTTP requests"
		else
			result T5-link FAIL "$_o"
		fi
	else
		result T5-link SKIP "no manual download (online phase missing?)"
	fi
	smoke_all
	snapshot_diff offline
}

case "$PHASE" in
online) phase_online ;;
offline) phase_offline ;;
all)
	phase_online
	DITTO_SPIKE_OFFLINE=proxy
	phase_offline
	;;
*) echo "unknown phase: $PHASE" >&2; exit 2 ;;
esac

echo "SUMMARY phase=$PHASE fails=$FAILS logs=$LOGS"
[ "$FAILS" = 0 ]
