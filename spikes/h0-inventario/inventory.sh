#!/bin/sh
# inventory.sh - read-only host inventory for ditto (spike H0, issue #3).
#
# Records OS, libc, CPU (AVX2) and the host binaries ditto cares about
# (arch.md section 1, categories B and C) into a single simple-TOML file.
#
# Guarantees:
#   - POSIX sh (dash, busybox ash, bash --posix, macOS /bin/sh).
#   - Read-only: the only file written is <outdir>/<label>.txt.
#   - No network access.
#   - Anonymized: no hostname, no IPs, no username; $HOME is shown as "~".
#
# Usage: inventory.sh [-n LABEL] [-o OUTDIR]
#   -n LABEL   anonymous host label (default: host-<cksum of hostname>)
#   -o OUTDIR  output directory (default: ./out)
set -eu

INVENTORY_FORMAT=1
PROBE_TIMEOUT=10

usage() {
	cat <<'EOF'
Usage: inventory.sh [-n LABEL] [-o OUTDIR]
  -n LABEL   anonymous host label, [A-Za-z0-9._-] (default: host-<checksum>)
  -o OUTDIR  output directory (default: ./out)
EOF
}

die() {
	printf 'inventory.sh: %s\n' "$1" >&2
	exit 2
}

label=""
outdir="./out"
while [ $# -gt 0 ]; do
	case "$1" in
	-n)
		[ $# -ge 2 ] || die "-n needs a value"
		label=$2
		shift 2
		;;
	-o)
		[ $# -ge 2 ] || die "-o needs a value"
		outdir=$2
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 2
		;;
	esac
done

real_host=$(uname -n 2>/dev/null || echo unknown)
real_user=$(id -un 2>/dev/null || echo "${USER:-${LOGNAME:-}}")
home_dir=${HOME:-}

if [ -z "$label" ]; then
	sum=$(printf '%s' "$real_host" | cksum | cut -d ' ' -f 1)
	label="host-$sum"
fi
case "$label" in
'' | .* | *[!A-Za-z0-9._-]*) die "invalid label '$label' (use [A-Za-z0-9._-], not starting with '.')" ;;
esac

# replace_all STRING NEEDLE REPLACEMENT
replace_all() {
	ra_s=$1
	ra_n=$2
	ra_r=$3
	ra_out=""
	if [ -z "$ra_n" ]; then
		printf '%s' "$ra_s"
		return 0
	fi
	while :; do
		case "$ra_s" in
		*"$ra_n"*)
			ra_out="$ra_out${ra_s%%"$ra_n"*}$ra_r"
			ra_s=${ra_s#*"$ra_n"}
			;;
		*) break ;;
		esac
	done
	printf '%s' "$ra_out$ra_s"
}

# anonymize STRING: drop characters that would break TOML strings and hide
# $HOME, the hostname and the username.
anonymize() {
	# shellcheck disable=SC1003 # deleting a literal backslash, not escaping a quote
	an_s=$(printf '%s' "$1" | tr -d '\r\033"\\' | tr '\t' ' ')
	case "$home_dir" in
	'' | /) ;;
	*) an_s=$(replace_all "$an_s" "$home_dir" "~") ;;
	esac
	if [ "${#real_host}" -ge 3 ]; then
		an_s=$(replace_all "$an_s" "$real_host" "<host>")
	fi
	if [ "${#real_user}" -ge 3 ] && [ "$real_user" != root ]; then
		an_s=$(replace_all "$an_s" "$real_user" "<user>")
	fi
	printf '%s' "$an_s"
}

# kv KEY VALUE: one TOML string entry.
kv() {
	printf '%s = "%s"\n' "$1" "$(anonymize "$2")"
}

# Old busybox only accepts "timeout -t SECS"; use timeout only if it works.
have_timeout=no
if command -v timeout >/dev/null 2>&1 && timeout 5 true </dev/null >/dev/null 2>&1; then
	have_timeout=yes
fi

# first_line CMD [ARGS...]: first meaningful line of combined stdout/stderr,
# never fails. Skips "unrecognized option" errors so that busybox applets
# report their "BusyBox vX" banner instead; also skips allocator warnings
# (jemalloc under QEMU) and empty lines.
first_line() {
	if [ "$have_timeout" = yes ]; then
		fl_out=$(timeout "$PROBE_TIMEOUT" "$@" </dev/null 2>&1 | head -n 20 || true)
	else
		fl_out=$("$@" </dev/null 2>&1 | head -n 20 || true)
	fi
	printf '%s\n' "$fl_out" | awk '
		NR == 1 { first = $0 }
		/(unrecognized|illegal|invalid|unknown) option/ || /[Ii]llegal option/ { next }
		/^<jemalloc>/ || /^[Ww][Aa][Rr][Nn][Ii][Nn][Gg]/ || $0 == "" { next }
		{ print; found = 1; exit }
		END { if (!found) print first }'
}

# extract_version RAW: "version=X" (lazygit) or first dotted number.
extract_version() {
	printf '%s\n' "$1" | awk '{
		if (match($0, /version=[0-9]+(\.[0-9]+)+/)) {
			print substr($0, RSTART + 8, RLENGTH - 8); exit
		}
		if (match($0, /[0-9]+(\.[0-9]+)+/)) {
			print substr($0, RSTART, RLENGTH); exit
		}
		# Plain integer word, e.g. "Apple gzip 475".
		for (i = 1; i <= NF; i++) if ($i ~ /^v?[0-9]+$/) { sub(/^v/, "", $i); print $i; exit }
	}'
}

os=$(uname -s 2>/dev/null || echo unknown)

# On macOS, /usr/bin/{git,cc,python3,...} are stubs that open the
# "install Command Line Tools" dialog when the CLT are missing.
clt_missing=no
if [ "$os" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then
	clt_missing=yes
fi

is_clt_stub() {
	[ "$clt_missing" = yes ] || return 1
	case "$1" in
	/usr/bin/git | /usr/bin/cc | /usr/bin/python3 | /usr/bin/clang | /usr/bin/gcc) return 0 ;;
	esac
	return 1
}

# probe KEY CATEGORY VERSION_ARG CANDIDATE...
probe() {
	pr_key=$1
	pr_cat=$2
	pr_arg=$3
	shift 3
	pr_name=""
	pr_path=""
	for pr_c in "$@"; do
		if pr_p=$(command -v "$pr_c" 2>/dev/null) && [ -n "$pr_p" ]; then
			pr_name=$pr_c
			pr_path=$pr_p
			break
		fi
	done
	emit_bin "$pr_key" "$pr_cat" "$pr_arg" "$pr_name" "$pr_path"
}

# emit_bin KEY CATEGORY VERSION_ARG NAME PATH
emit_bin() {
	printf '\n[bin.%s]\n' "$1"
	kv category "$2"
	if [ -z "$5" ]; then
		printf 'found = false\n'
		return 0
	fi
	printf 'found = true\n'
	kv name "$4"
	kv path "$5"
	if is_clt_stub "$5"; then
		kv version ""
		kv raw "macOS CLT stub (Command Line Tools not installed)"
		return 0
	fi
	eb_raw=$(first_line "$5" "$3")
	kv version "$(extract_version "$eb_raw")"
	kv raw "$eb_raw"
}

# os_release_field FIELD: value from /etc/os-release, without sourcing it.
os_release_field() {
	[ -r /etc/os-release ] || return 0
	sed -n "s/^$1=//p" /etc/os-release | head -n 1 | tr -d '"'"'"
}

detect_libc() {
	libc=unknown
	libc_version=""
	libc_raw=""
	if [ "$os" = Darwin ]; then
		libc=darwin
		return 0
	fi
	dl_g=$(getconf GNU_LIBC_VERSION 2>/dev/null || true)
	case "$dl_g" in
	glibc*)
		libc=glibc
		libc_version=$(extract_version "$dl_g")
		libc_raw=$dl_g
		return 0
		;;
	esac
	if command -v ldd >/dev/null 2>&1; then
		dl_l=$(ldd --version 2>&1 || true)
		case "$dl_l" in
		*musl*)
			libc=musl
			libc_version=$(printf '%s\n' "$dl_l" | sed -n 's/^Version //p' | head -n 1)
			libc_raw=$(printf '%s\n' "$dl_l" | head -n 1)
			return 0
			;;
		*GLIBC* | *"GNU libc"* | *glibc*)
			libc=glibc
			libc_raw=$(printf '%s\n' "$dl_l" | head -n 1)
			libc_version=$(printf '%s\n' "$libc_raw" | awk '{ print $NF }')
			return 0
			;;
		esac
	fi
	for dl_f in /lib/ld-musl-*; do
		if [ -e "$dl_f" ]; then
			libc=musl
			libc_raw=$dl_f
			return 0
		fi
	done
}

detect_cpu() {
	cpu_model=""
	cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo "")
	avx2=n/a
	case "$os" in
	Darwin)
		cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
		dc_a=$(sysctl -n hw.optional.avx2_0 2>/dev/null || true)
		case "$dc_a" in
		1) avx2=yes ;;
		0) avx2=no ;;
		esac
		;;
	Linux)
		if [ -r /proc/cpuinfo ]; then
			cpu_model=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n 1)
			case "$arch" in
			x86_64 | amd64 | i?86)
				if awk '/^flags/ { for (i = 1; i <= NF; i++) if ($i == "avx2") f = 1 } END { exit !f }' /proc/cpuinfo; then
					avx2=yes
				else
					avx2=no
				fi
				;;
			esac
		fi
		;;
	esac
}

in_container=no
if [ -e /.dockerenv ] || [ -e /run/.containerenv ]; then
	in_container=yes
fi

arch=$(uname -m 2>/dev/null || echo unknown)
detect_libc
detect_cpu

mkdir -p "$outdir"
outfile="$outdir/$label.txt"
tmpfile="$outfile.tmp"

{
	printf '# ditto host inventory (spike H0, issue #3)\n'
	printf 'format = %s\n' "$INVENTORY_FORMAT"
	printf '\n[host]\n'
	kv label "$label"
	kv date "$(date -u +%Y-%m-%d)"
	kv in_container "$in_container"
	kv os "$os"
	kv arch "$arch"
	kv kernel "$(uname -r 2>/dev/null || true)"
	kv distro_id "$(os_release_field ID)"
	kv distro_version "$(os_release_field VERSION_ID)"
	kv distro_name "$(os_release_field PRETTY_NAME)"
	if [ "$os" = Darwin ]; then
		kv macos_version "$(sw_vers -productVersion 2>/dev/null || true)"
		kv macos_clt "$([ "$clt_missing" = yes ] && echo missing || echo installed)"
	else
		kv macos_version ""
		kv macos_clt ""
	fi
	kv libc "$libc"
	kv libc_version "$libc_version"
	kv libc_raw "$libc_raw"
	kv cpu_model "$cpu_model"
	kv cpu_count "$cpu_count"
	kv avx2 "$avx2"

	# Category B: hard prerequisites (arch.md section 1).
	probe git host-hard --version git
	probe curl host-hard --version curl
	probe wget host-hard --version wget
	probe tar host-hard --version tar
	probe unzip host-hard -v unzip
	# Category B: soft prerequisites.
	probe cc host-soft --version cc
	probe ssh host-soft -V ssh
	# Category B: system base.
	sh_path=${SHELL:-}
	if [ -n "$sh_path" ] && [ -x "$sh_path" ]; then
		emit_bin shell host-base --version "${sh_path##*/}" "$sh_path"
	else
		emit_bin shell host-base --version "" ""
	fi
	probe bash host-base --version bash
	probe zsh host-base --version zsh
	probe gzip host-base --version gzip
	probe xz host-base --version xz
	# Category C: selectables.
	probe nvim selectable --version nvim
	probe rg selectable --version rg
	probe fd selectable --version fd fdfind
	probe fzf selectable --version fzf
	probe lazygit selectable --version lazygit
	probe node selectable --version node
	probe python3 selectable --version python3
	probe go selectable version go
	# Not selectable, but relevant for interference (arch.md section 1, H0.1b).
	probe mise managed --version mise
	probe conda passthrough --version conda
} >"$tmpfile"
mv "$tmpfile" "$outfile"
printf '%s\n' "$outfile"
