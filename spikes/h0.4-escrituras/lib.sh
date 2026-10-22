# shellcheck shell=sh
# shellcheck disable=SC2016 # single-quoted $ in generated wrapper values, on purpose
# Spike H0.4 — reusable library on top of H0.3 (which loads H0.1). Adds:
#   * filesystem snapshots (path, type, size, mtime) and their diff;
#   * the extra downloads of this spike, each verified with an embedded sha256
#     (Node.js for npx MCPs, StyLua cross-check of the Mason install);
#   * OpenCode in the mise config (H0.1 lock) and its wrapper (H0.2 variables);
#   * the "proposed" mechanisms that close the escapes found (h04_apply_proposed).
#
#   H04_DIR=spikes/h0.4-escrituras
#   . "$H04_DIR/lib.sh"
#
# The H0.1/H0.3 directories are only read, never modified. Throwaway code.

: "${H04_DIR:?set H04_DIR to the spike directory before sourcing lib.sh}"
H03_DIR=${H03_DIR:-$H04_DIR/../h0.3-aislamiento-lazyvim}
# shellcheck source=../h0.3-aislamiento-lazyvim/lib.sh
. "$H03_DIR/lib.sh"

# ---------------------------------------------------------------------------
# Pinned downloads (sha256 embedded, as ditto would embed them).
# ---------------------------------------------------------------------------

H04_NODE_VERSION=22.23.4
# From https://nodejs.org/dist/v22.23.4/SHASUMS256.txt
h04_node_sha256() {
	case "$1" in
	node-v22.23.4-darwin-arm64.tar.gz) echo c9e1dbc748b33ed2d14f42445191ecaf14c56259c7a9a26d0042c49ec2b66428 ;;
	node-v22.23.4-linux-arm64.tar.gz) echo f7a1e486dbc8b286847815b477d4fb5e9fb963ed4489c3e1588853d685f589f9 ;;
	node-v22.23.4-linux-x64.tar.gz) echo b8492284c76a54baf58d61668dd0e41ee0fc98adabf9503d30f05d08f55b4406 ;;
	*) return 1 ;;
	esac
}

# Mason: registry pinned to a release tag, StyLua pinned to a version. The
# digests come from the GitHub API (`digest` field of each release asset).
H04_MASON_REGISTRY=2026-10-22-ill-fund
H04_MASON_REGISTRY_ZIP_SHA256=4819746edb4b9e8644af23c058b716003291df06b746e5b5e5b9bedfdf603085
H04_STYLUA_VERSION=v2.6.0
h04_stylua_sha256() {
	case "$1" in
	stylua-macos-aarch64.zip) echo dab9b66d340ca5ffc8225211f1dcf89b84783e09b8cbec8c518497eba81f3c42 ;;
	stylua-linux-aarch64.zip) echo 8e67539e5fdf7a81cd03cf592b0df18d3bb96ee17a5ea5d9bf67b86387b903b0 ;;
	stylua-linux-x86_64.zip) echo a485f72bbfa22e4642e77a84b5edc2611a5cab7477b34e2e709dd8f78e919895 ;;
	*) return 1 ;;
	esac
}

# Mason plugins, pinned by commit (lazy-lock.json), as every other plugin.
H04_MASON_COMMIT=2a6940af80375532e5e9e7c1f2fc6319a1b7a69d           # mason.nvim v2.3.1
H04_MASON_LSPCONFIG_COMMIT=a5671269a1ddfa7790cdf97c14e600e269da550f # mason-lspconfig.nvim v2.3.0

# h04_fetch_verified <url> <file> <sha256> — download, verify, delete on mismatch.
h04_fetch_verified() {
	mkdir -p "$(dirname "$2")"
	if [ ! -f "$2" ] || [ "$(ditto_sha256 "$2")" != "$3" ]; then
		_ditto_fetch "$1" "$2.part" || return 1
		mv "$2.part" "$2"
	fi
	_got=$(ditto_sha256 "$2")
	if [ "$_got" != "$3" ]; then
		rm -f "$2"
		echo "sha256 mismatch for $1: got $_got want $3" >&2
		return 1
	fi
	echo "sha256 OK $(basename "$2") $3" >&2
}

# h04_node_asset — Node.js tarball name for this host.
h04_node_asset() {
	case "$(ditto_os)-$(ditto_arch)" in
	macos-arm64) echo "node-v$H04_NODE_VERSION-darwin-arm64.tar.gz" ;;
	linux-arm64) echo "node-v$H04_NODE_VERSION-linux-arm64.tar.gz" ;;
	linux-x64) echo "node-v$H04_NODE_VERSION-linux-x64.tar.gz" ;;
	*) return 1 ;;
	esac
}

# h04_install_node <download-dir> — Node.js into $DITTO_ROOT/spike/node: the
# stand-in for a mise runtime (MCPs via npx). Prints its bin dir.
h04_install_node() {
	_a=$(h04_node_asset) || return 1
	_sum=$(h04_node_sha256 "$_a") || return 1
	h04_fetch_verified "https://nodejs.org/dist/v$H04_NODE_VERSION/$_a" "$1/node/$_a" "$_sum" || return 1
	_dst="$DITTO_ROOT/spike/node"
	mkdir -p "$_dst"
	tar -xzf "$1/node/$_a" -C "$_dst" --strip-components 1 || return 1
	echo "$_dst/bin"
}

# h04_stylua_asset — the asset Mason picks for this host (registry package.yaml).
h04_stylua_asset() {
	case "$(ditto_os)-$(ditto_arch)" in
	macos-arm64) echo stylua-macos-aarch64.zip ;;
	linux-arm64) echo stylua-linux-aarch64.zip ;;
	linux-x64) echo stylua-linux-x86_64.zip ;;
	*) return 1 ;;
	esac
}

# h04_verify_mason <download-dir> — Mason downloads without a pinned sha256 of
# its own (H0.5): cross-check what it installed against our own verified
# download. Prints "OK ..." or "MISMATCH ..." lines; returns 1 on mismatch.
h04_verify_mason() {
	_rc=0
	_a=$(h04_stylua_asset) || return 1
	h04_fetch_verified "https://github.com/JohnnyMorganz/StyLua/releases/download/$H04_STYLUA_VERSION/$_a" \
		"$1/stylua/$_a" "$(h04_stylua_sha256 "$_a")" || return 1
	rm -rf "$1/stylua/x"
	mkdir -p "$1/stylua/x"
	(cd "$1/stylua/x" && unzip -q "../$_a") || return 1
	_want=$(ditto_sha256 "$1/stylua/x/stylua")
	_inst="$DITTO_ROOT/data/nvim/mason/packages/stylua/stylua"
	_have=$( [ -f "$_inst" ] && ditto_sha256 "$_inst" || echo absent)
	if [ "$_have" = "$_want" ]; then echo "OK stylua binary = verified $_a ($_want)"; else echo "MISMATCH stylua: installed $_have, verified $_want"; _rc=1; fi
	h04_fetch_verified "https://github.com/mason-org/mason-registry/releases/download/$H04_MASON_REGISTRY/registry.json.zip" \
		"$1/registry/registry.json.zip" "$H04_MASON_REGISTRY_ZIP_SHA256" || return 1
	rm -rf "$1/registry/x"
	mkdir -p "$1/registry/x"
	(cd "$1/registry/x" && unzip -q ../registry.json.zip) || return 1
	_rw=$(ditto_sha256 "$1/registry/x/registry.json")
	_ri=$(find "$DITTO_ROOT/data/nvim/mason/registries" -name registry.json 2>/dev/null | head -n 1)
	_rh=$( [ -n "$_ri" ] && ditto_sha256 "$_ri" || echo absent)
	if [ "$_rh" = "$_rw" ]; then echo "OK mason registry.json = verified $H04_MASON_REGISTRY ($_rw)"; else echo "MISMATCH registry.json: installed $_rh, verified $_rw"; _rc=1; fi
	return "$_rc"
}

# ---------------------------------------------------------------------------
# Tools, wrappers and starter.
# ---------------------------------------------------------------------------

# h04_write_mise_config <file> [all|opencode] — H0.3 subset plus OpenCode with
# the variant rule of H0.1/H0.2. "opencode" installs only OpenCode.
h04_write_mise_config() {
	if [ "${2:-all}" = opencode ]; then
		echo '# Generated by spikes/h0.4-escrituras (OpenCode only).' >"$1"
		echo '[tools]' >>"$1"
	else
		h03_write_mise_config "$1" || return 1
	fi
	_libc=$(ditto_libc)
	{
		echo
		_ditto_opencode_entry "$(ditto_opencode_variant)" "${_libc%% *}"
	} >>"$1"
}

# h04_install_tools [all|opencode] — mise (sha256) + install --locked (H0.1 lock).
h04_install_tools() {
	ditto_mise_bootstrap || return 1
	h04_write_mise_config "$DITTO_MISE_CONFIG" "${1:-all}" || return 1
	cp "$H01_DIR/mise.lock" "$DITTO_MISE_LOCK"
	ditto_mise install --locked >&2
}

# h04_write_opencode_wrapper <abs-opencode> <node-bin-or-empty> [VAR=value...]
# — the H0.2 variables through the H0.3 tool wrapper (restores DITTO_ORIG_*
# first). MCP runtimes (node) only in its PATH.
h04_write_opencode_wrapper() {
	_oc=$1 _nb=$2
	shift 2
	mkdir -p "$DITTO_ROOT/tmp"
	set -- 'XDG_CONFIG_HOME=$DITTO_ROOT/config' 'XDG_DATA_HOME=$DITTO_ROOT/data' \
		'XDG_STATE_HOME=$DITTO_ROOT/state' 'XDG_CACHE_HOME=$DITTO_ROOT/cache' \
		'OPENCODE_CONFIG_DIR=$DITTO_ROOT/config/opencode' 'TMPDIR=$DITTO_ROOT/tmp' \
		'OPENCODE_DISABLE_AUTOUPDATE=1' "$@"
	[ -n "$_nb" ] && set -- "$@" "PATH=$_nb:\$PATH"
	h03_write_tool_wrapper opencode "$_oc" "$@"
}

# h04_install_starter <dest-dir> — copy of the H0.3 starter with Mason enabled
# (pinned registry, nothing auto-installed) instead of spike-offline.lua, and
# the two Mason plugins pinned in lazy-lock.json. Then H0.3's installer.
h04_install_starter() {
	_s="$1/starter"
	rm -rf "$_s"
	mkdir -p "$1"
	cp -R "$H03_DIR/starter" "$_s"
	rm -f "$_s/lua/plugins/spike-offline.lua"
	sed "s/@H04_MASON_REGISTRY@/$H04_MASON_REGISTRY/" "$H04_DIR/starter/spike-h04.lua" >"$_s/lua/plugins/spike-h04.lua"
	awk -v m="$H04_MASON_COMMIT" -v l="$H04_MASON_LSPCONFIG_COMMIT" '
		/^{/ { print; print "  \"mason-lspconfig.nvim\": { \"branch\": \"main\", \"commit\": \"" l "\" },"; print "  \"mason.nvim\": { \"branch\": \"main\", \"commit\": \"" m "\" },"; next }
		{ print }' "$H03_DIR/starter/lazy-lock.json" >"$_s/lazy-lock.json"
	h03_install_starter "$_s"
}

# h04_apply_proposed — rewrites the wrappers/rc with the mechanisms proposed
# by this spike (see RESULTS.md). Requires the tools to be installed.
#   lazygit:  TMPDIR=$DITTO_ROOT/tmp (lazygit-<uid> temp dir)
#   opencode: npm_config_cache=$DITTO_ROOT/cache/npm (npx MCPs -> ~/.npm)
#   nvim:     npm_config_cache too (Mason npm packages), saved/restored
h04_apply_proposed() {
	H03_SAVED_VARS="$H03_SAVED_VARS npm_config_cache"
	h03_write_nvim_wrapper "$(h03_tool nvim)" || return 1
	_w="$DITTO_ROOT/bin/nvim"
	awk '/^exec / { print "export npm_config_cache=\"$DITTO_ROOT/cache/npm\""; print "mkdir -p \"$npm_config_cache\"" } { print }' "$_w" >"$_w.new" &&
		mv "$_w.new" "$_w" && chmod 0755 "$_w"
	h03_write_tool_wrapper lazygit "$(h03_tool lazygit)" \
		'CONFIG_DIR=$DITTO_ROOT/config/lazygit' \
		'LG_CONFIG_FILE=${LG_CONFIG_FILE:-$DITTO_ROOT/config/lazygit/config.yml}' \
		'TMPDIR=$DITTO_ROOT/tmp' || return 1
	h04_write_opencode_wrapper "$(h03_tool opencode)" "${H04_NODE_BIN:-}" 'npm_config_cache=$DITTO_ROOT/cache/npm' || return 1
	h03_write_host_sh
}

# ---------------------------------------------------------------------------
# Snapshots.
# ---------------------------------------------------------------------------

# h04_snap <out> <root> [prune-path...] — one line per entry under <root>:
# path<TAB>type<TAB>size<TAB>mtime, sorted. Pruned paths (and their
# contents) are left out. Stays on one filesystem (-xdev). Read-only.
h04_snap() {
	_o=$1 _root=$2
	shift 2
	_depth=""
	[ -n "${H04_SNAP_MAXDEPTH:-}" ] && _depth="-maxdepth $H04_SNAP_MAXDEPTH"
	set -- "$@" /proc /sys /dev
	_expr=""
	for _p in "$@"; do
		_expr="$_expr -o -path $(_h03_q "$_p")"
	done
	_expr=${_expr# -o }
	if [ ! -e "$_root" ]; then
		: >"$_o"
		return 0
	fi
	if find / -maxdepth 0 -printf '' 2>/dev/null; then
		# shellcheck disable=SC2086
		eval "find $(_h03_q "$_root") $_depth -xdev \\( $_expr \\) -prune -o -printf '%p\t%y\t%s\t%T@\n'" 2>/dev/null
	else
		# shellcheck disable=SC2086
		eval "find $(_h03_q "$_root") $_depth -xdev \\( $_expr \\) -prune -o -exec stat -f '%N%t%HT%t%z%t%Fm' {} +" 2>/dev/null
	fi | LC_ALL=C sort >"$_o"
}

# h04_snap_hash <file> — sha256 of a snapshot listing.
h04_snap_hash() {
	ditto_sha256 "$1"
}

# h04_diff <before> <after> — A (added), D (deleted), M (type/size/mtime
# changed) lines: "<op><TAB>path<TAB>type".
h04_diff() {
	awk -F '\t' '
		NR == FNR { old[$1] = $2 "\t" $3 "\t" $4; t[$1] = $2; next }
		{ seen[$1] = 1
		  if (!($1 in old)) { print "A\t" $1 "\t" $2 }
		  else if (old[$1] != $2 "\t" $3 "\t" $4) { print "M\t" $1 "\t" $2 } }
		END { for (p in old) if (!(p in seen)) print "D\t" p "\t" t[p] }
	' "$1" "$2" | LC_ALL=C sort -k2
}
