# shellcheck shell=sh
# Spike H0.1 — reusable library to run a pinned, fully isolated mise inside
# a .ditto/ directory. Source it (POSIX sh) and call the functions:
#
#   . spikes/h0.1-mise-aislado/env.sh
#   ditto_mise_env /path/to/.ditto      # export the MISE_* isolation vars
#   ditto_mise_bootstrap                # download + sha256-verify mise
#   ditto_mise install                  # run the isolated mise
#
# Throwaway spike code: the production version lives in internal/installer.

# Pinned mise release. Hashes come from the release SHASUMS256.txt and are
# embedded here (as ditto will embed them) so a compromised download cannot
# also replace the expected checksum.
DITTO_MISE_VERSION="2026.10.15"

# ditto_mise_sha256 <asset> — prints the embedded sha256 for a mise asset.
ditto_mise_sha256() {
	case "$1" in
	mise-v2026.10.15-linux-arm64) echo 3abbaac305a465ef038eb4ea07b961c037a8b639108005e43f8e2c00a8f67c11 ;;
	mise-v2026.10.15-linux-arm64-musl) echo 823b94a7425c4781d475357cb2064bfafddc13cf66b7f2927b65d96f49bbe73c ;;
	mise-v2026.10.15-linux-x64) echo e3b186d4c70627f27037be615becaf4acfb30e41fb6a1819486717dc94e4e2a9 ;;
	mise-v2026.10.15-linux-x64-musl) echo 5daa5f70c1588bb27ffecb275b46dbafcab0f6fc93a893138ba4d8cae6074b60 ;;
	mise-v2026.10.15-macos-arm64) echo 826c4833fa7437a63f6027b86bc10c8b61b1163dc793c03ecde92f68ad167890 ;;
	mise-v2026.10.15-macos-x64) echo ea45cc6e787d412deb8e069eec57875c71863e33a36acf69dd59791c27c9c073 ;;
	*) return 1 ;;
	esac
}

# ditto_os / ditto_arch — mise naming (linux|macos, x64|arm64).
ditto_os() {
	case "$(uname -s)" in
	Linux) echo linux ;;
	Darwin) echo macos ;;
	*) echo "unsupported OS: $(uname -s)" >&2; return 1 ;;
	esac
}

ditto_arch() {
	case "$(uname -m)" in
	x86_64 | amd64) echo x64 ;;
	aarch64 | arm64) echo arm64 ;;
	*) echo "unsupported arch: $(uname -m)" >&2; return 1 ;;
	esac
}

# ditto_libc — prints "musl", "glibc <major.minor>" or "none" (macOS).
ditto_libc() {
	if [ "$(uname -s)" = Darwin ]; then
		echo none
		return 0
	fi
	if ls /lib/ld-musl-* >/dev/null 2>&1; then
		echo musl
		return 0
	fi
	_v=$(ldd --version 2>&1 | head -n 1 | sed -n 's/.* \([0-9][0-9]*\.[0-9][0-9]*\)$/\1/p')
	echo "glibc ${_v:-unknown}"
}

# ditto_glibc_at_least <major.minor> — true if the host glibc is >= the
# given version. False on musl and macOS.
ditto_glibc_at_least() {
	set -- "$1" "$(ditto_libc)"
	case "$2" in glibc\ *) ;; *) return 1 ;; esac
	_have=${2#glibc }
	[ "$(printf '%s\n%s\n' "$1" "$_have" | sort -t. -k1,1n -k2,2n | head -n 1)" = "$1" ]
}

# ditto_mise_asset — mise release asset for this host. On Linux the musl
# build is used everywhere: it is static, so it runs on glibc 2.27 and on
# Alpine alike (see RESULTS.md).
ditto_mise_asset() {
	_os=$(ditto_os) || return 1
	_arch=$(ditto_arch) || return 1
	if [ "$_os" = linux ]; then
		echo "mise-v${DITTO_MISE_VERSION}-linux-${_arch}-musl"
	else
		echo "mise-v${DITTO_MISE_VERSION}-${_os}-${_arch}"
	fi
}

# ditto_mise_env <ditto_dir> — exports every variable needed so mise reads
# and writes only under <ditto_dir>/mise. These must only ever be set for
# the mise process (never exported to the user's subshell).
ditto_mise_env() {
	[ -n "${1:-}" ] || { echo "ditto_mise_env: missing <ditto_dir>" >&2; return 1; }
	mkdir -p "$1/mise"
	DITTO_DIR=$(cd "$1" && pwd -P)
	_m="$DITTO_DIR/mise"
	export DITTO_DIR
	export DITTO_MISE_BIN="$_m/bin/mise"
	# Directories.
	export MISE_DATA_DIR="$_m"
	export MISE_CACHE_DIR="$_m/cache"
	export MISE_STATE_DIR="$_m/state"
	export MISE_TMP_DIR="$_m/tmp"
	export MISE_CONFIG_DIR="$_m"
	export MISE_SYSTEM_CONFIG_DIR="$_m/system"
	export MISE_SYSTEM_DATA_DIR="$_m/system"
	# Config files: one global file, a non-existent system file, and config
	# discovery stopped at .ditto/mise so a workspace mise.toml or
	# .tool-versions in a parent directory is never picked up.
	export MISE_GLOBAL_CONFIG_FILE="$_m/config.toml"
	export MISE_GLOBAL_CONFIG_ROOT="$_m"
	export MISE_SYSTEM_CONFIG_FILE="$_m/system/config.toml"
	export MISE_CEILING_PATHS="$DITTO_DIR"
	export MISE_IGNORED_CONFIG_PATHS="$HOME/.config/mise"
	# Trust: only our own config, by path, so `mise trust` never writes state
	# elsewhere and no prompt appears.
	export MISE_TRUSTED_CONFIG_PATHS="$_m"
	# Non-interactive, no telemetry, no self-update noise.
	export MISE_YES=1
	export MISE_DISABLE_UPDATE_WARNING=1
	export MISE_USE_VERSIONS_HOST_TRACK=0
	export MISE_SELF_UPDATE_AUTO=0
	export MISE_AUTO_INSTALL=0
	export MISE_NOT_FOUND_AUTO_INSTALL=0
	export MISE_EXPERIMENTAL=1
	# Lockfile lives next to the global config: .ditto/mise/mise.lock.
	export MISE_LOCKFILE=1
	unset MISE_SHIMS_DIR MISE_INSTALLS_DIR MISE_ENV 2>/dev/null || true
}

# ditto_mise_unexport — drops every MISE_* variable (what the subshell must
# see). Uses `env` so it also works for names unknown to this script.
ditto_mise_unexport() {
	for _v in $(env | sed -n 's/^\(MISE_[A-Za-z0-9_]*\)=.*/\1/p'); do
		unset "$_v"
	done
}

# _ditto_fetch <url> <dest> — HTTPS download with curl or wget.
_ditto_fetch() {
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$2" "$1"
	else
		echo "need curl or wget" >&2
		return 1
	fi
}

# ditto_sha256 <file> — prints the sha256 of a file (Linux or macOS).
ditto_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

# ditto_mise_bootstrap — downloads the pinned mise into $DITTO_MISE_BIN and
# verifies it against the embedded sha256. Idempotent. Requires
# ditto_mise_env first. Set DITTO_MISE_FROM=<file> to use a local copy.
ditto_mise_bootstrap() {
	[ -n "${DITTO_MISE_BIN:-}" ] || { echo "call ditto_mise_env first" >&2; return 1; }
	_asset=$(ditto_mise_asset) || return 1
	_want=$(ditto_mise_sha256 "$_asset") || { echo "no embedded sha256 for $_asset" >&2; return 1; }
	if [ -x "$DITTO_MISE_BIN" ] && [ "$(ditto_sha256 "$DITTO_MISE_BIN")" = "$_want" ]; then
		return 0
	fi
	mkdir -p "$(dirname "$DITTO_MISE_BIN")"
	_tmp="$DITTO_MISE_BIN.download"
	if [ -n "${DITTO_MISE_FROM:-}" ]; then
		cp "$DITTO_MISE_FROM" "$_tmp"
	else
		_ditto_fetch "https://github.com/jdx/mise/releases/download/v${DITTO_MISE_VERSION}/${_asset}" "$_tmp" || return 1
	fi
	_got=$(ditto_sha256 "$_tmp")
	if [ "$_got" != "$_want" ]; then
		rm -f "$_tmp"
		echo "sha256 mismatch for $_asset: got $_got want $_want" >&2
		return 1
	fi
	chmod 0755 "$_tmp"
	mv "$_tmp" "$DITTO_MISE_BIN"
	echo "mise $DITTO_MISE_VERSION ($_asset) sha256 OK: $_want" >&2
}

# ditto_mise <args...> — runs the isolated mise from inside .ditto/mise so
# the current directory can never contribute a project config.
#
# MISE_* alone is not enough: mise's sigstore client (artifact attestation
# checks) keeps a TUF cache in the platform cache dir, i.e.
# ~/Library/Caches/dev.sigstore.sigstore-rust on macOS and
# ${XDG_CACHE_HOME:-~/.cache}/sigstore-rust on Linux, ignoring MISE_CACHE_DIR.
# So, for the mise process only, HOME and XDG_* point inside .ditto/mise/home.
# DITTO_MISE_ISOLATE_HOME=0 disables this (used to demonstrate the leak).
ditto_mise() {
	if [ "${DITTO_MISE_ISOLATE_HOME:-1}" = 1 ]; then
		_h="$DITTO_DIR/mise/home"
		mkdir -p "$_h" "$DITTO_DIR/mise/tmp"
		(cd "$DITTO_DIR/mise" && HOME="$_h" XDG_CACHE_HOME="$_h/.cache" \
			XDG_CONFIG_HOME="$_h/.config" XDG_DATA_HOME="$_h/.local/share" \
			XDG_STATE_HOME="$_h/.local/state" TMPDIR="$DITTO_DIR/mise/tmp" \
			"$DITTO_MISE_BIN" "$@")
	else
		(cd "$DITTO_DIR/mise" && "$DITTO_MISE_BIN" "$@")
	fi
}

# ---------------------------------------------------------------------------
# Component catalogue validated by the spike (pinned versions and backends).
# ---------------------------------------------------------------------------

DITTO_V_NVIM="0.12.6"        # aqua:neovim/neovim (glibc >= 2.31, macOS)
DITTO_V_NVIM_LEGACY="0.12.5" # github:neovim/neovim-releases (glibc 2.27+)
DITTO_V_RG="15.2.0"
DITTO_V_FD="10.5.0"
DITTO_V_FZF="0.74.5"
DITTO_V_LAZYGIT="0.66.2"
DITTO_V_TREESITTER="0.27.1"  # conda:tree-sitter-cli (conda-forge)
DITTO_V_OPENCODE="1.19.3"

# ditto_has_avx2 — true on x86_64 Linux hosts whose CPU reports avx2.
ditto_has_avx2() {
	[ -r /proc/cpuinfo ] && grep -qw avx2 /proc/cpuinfo
}

# ditto_nvim_tool — mise tool id for Neovim on this host, or empty if no
# prebuilt binary exists (musl: Neovim publishes no musl build).
ditto_nvim_tool() {
	case "$(ditto_libc)" in
	none) echo "aqua:neovim/neovim" ;;
	musl) echo "" ;;
	*)
		if ditto_glibc_at_least 2.31; then
			echo "aqua:neovim/neovim"
		else
			echo "github:neovim/neovim-releases"
		fi
		;;
	esac
}

# ditto_treesitter_tool — mise tool id for the tree-sitter CLI, or empty on
# musl. The upstream GitHub/aqua builds need glibc >= 2.39 (0.26+), so they
# fail even on Ubuntu 22.04; conda-forge builds target an old glibc and run
# on 2.27. conda-forge has no musl builds.
ditto_treesitter_tool() {
	if [ "$(ditto_libc)" = musl ]; then
		echo ""
	else
		echo "conda:tree-sitter-cli"
	fi
}

# ditto_opencode_variant — normal | baseline (x86_64 Linux without AVX2).
# DITTO_OPENCODE_VARIANT overrides the detection.
ditto_opencode_variant() {
	if [ -n "${DITTO_OPENCODE_VARIANT:-}" ]; then
		echo "$DITTO_OPENCODE_VARIANT"
	elif [ "$(ditto_os)" = linux ] && [ "$(ditto_arch)" = x64 ] && ! ditto_has_avx2; then
		echo baseline
	else
		echo normal
	fi
}

# _ditto_opencode_entry <variant> <libc> — TOML for OpenCode. The github
# backend picks the -musl asset by itself on musl hosts; -baseline must be
# named explicitly with a per-platform asset_pattern (the platform key has
# no libc, so the musl flavour is chosen here).
_ditto_opencode_entry() {
	printf '[tools."github:anomalyco/opencode"]\nversion = "%s"\n' "$DITTO_V_OPENCODE"
	if [ "$1" = baseline ]; then
		_suffix=baseline
		[ "$2" = musl ] && _suffix=baseline-musl
		printf 'platforms.linux-x64 = { asset_pattern = "opencode-linux-x64-%s.tar.gz" }\n' "$_suffix"
	fi
}

# ditto_write_config <file> [host|all] [opencode-variant] [libc] — writes the
# mise config.toml. "host" (default) is what ditto would generate for this
# host from profile + platform. "all" is the superset used to generate the
# shared mise.lock (both Neovim builds; OpenCode variant as given).
ditto_write_config() {
	_f=$1
	_mode=${2:-host}
	{
		echo '# Generated by spikes/h0.1-mise-aislado (ditto would generate this).'
		echo '[tools]'
		if [ "$_mode" = all ]; then
			echo "\"aqua:neovim/neovim\" = \"$DITTO_V_NVIM\""
			echo "\"github:neovim/neovim-releases\" = \"$DITTO_V_NVIM_LEGACY\""
		else
			case "$(ditto_nvim_tool)" in
			aqua:*) echo "\"aqua:neovim/neovim\" = \"$DITTO_V_NVIM\"" ;;
			github:*) echo "\"github:neovim/neovim-releases\" = \"$DITTO_V_NVIM_LEGACY\"" ;;
			*) echo '# neovim: no prebuilt binary for this libc (source=host)' ;;
			esac
		fi
		echo "\"github:BurntSushi/ripgrep\" = \"$DITTO_V_RG\""
		echo "\"aqua:sharkdp/fd\" = \"$DITTO_V_FD\""
		echo "\"aqua:junegunn/fzf\" = \"$DITTO_V_FZF\""
		echo "\"aqua:jesseduffield/lazygit\" = \"$DITTO_V_LAZYGIT\""
		if [ "$_mode" = all ] || [ -n "$(ditto_treesitter_tool)" ]; then
			echo "\"conda:tree-sitter-cli\" = \"$DITTO_V_TREESITTER\""
		else
			echo '# tree-sitter: no prebuilt binary for this libc (source=host/path)'
		fi
		echo
		if [ "$_mode" = all ]; then
			_ditto_opencode_entry "${3:-normal}" "${4:-glibc}"
		else
			_libc=$(ditto_libc)
			_ditto_opencode_entry "$(ditto_opencode_variant)" "${_libc%% *}"
		fi
	} >"$_f"
}
