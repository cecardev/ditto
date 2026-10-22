#!/bin/sh
# Spike H0.2 (#2): OpenCode isolation, data paths and release variants.
#
# Usage:
#   ./run.sh fetch            download the pinned release assets and verify sha256
#   ./run.sh macos            probe on this macOS host (temp HOME, nothing in the real $HOME)
#   ./run.sh linux            probe the Linux matrix in Docker (arm64 native, amd64 via qemu)
#   ./run.sh variants         start every Linux variant on every image (variant matrix)
#   ./run.sh noavx2           full probe of the normal x64 build on the no-AVX2 qemu CPU
#   ./run.sh tmpdir           check start-up with a missing TMPDIR per variant
#   ./run.sh all              fetch + macos + linux + noavx2 + variants + tmpdir
#
# Environment:
#   WORK      scratch dir for downloads and outputs (default: ./.work, gitignored)
#   VERSION   OpenCode release tag (default: v1.19.3; must match SHA256SUMS)
#   IMAGES    images for `linux` (default: ubuntu:18.04 ubuntu:22.04 alpine:3.20)
#   VARIANT_IMAGES  images for `variants` ("+libstdc++" installs it on Alpine first)
#
# Nothing here needs credentials. Network is used for the download and for
# `opencode models` (models.dev catalog), which is part of a normal start.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$here/.work}
VERSION=${VERSION:-v1.19.3}
IMAGES=${IMAGES:-"ubuntu:18.04 ubuntu:22.04 alpine:3.20"}
VARIANT_IMAGES=${VARIANT_IMAGES:-"ubuntu:18.04 ubuntu:22.04 rockylinux:8 alpine:3.20 alpine:3.20+libstdc++"}
REPO=anomalyco/opencode
mkdir -p "$WORK/out"

log() { printf '\n==> %s\n' "$*"; }

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

# fetch_asset <name>: download into its own dir, verify sha256, extract into
# $WORK/bin/<variant>/opencode.
fetch_asset() {
	name=$1
	variant=${name#opencode-}
	variant=${variant%.tar.gz}
	variant=${variant%.zip}
	bin="$WORK/bin/$variant/opencode"
	if [ -x "$bin" ]; then
		return 0
	fi
	want=$(awk -v n="$name" '$2 == n { print $1 }' "$here/SHA256SUMS")
	if [ -z "$want" ]; then
		echo "no pinned sha256 for $name" >&2
		return 1
	fi
	dl="$WORK/dl/$variant"
	mkdir -p "$dl" "$WORK/bin/$variant"
	curl -fsSL --proto '=https' -o "$dl/$name" \
		"https://github.com/$REPO/releases/download/$VERSION/$name"
	got=$(sha256_of "$dl/$name")
	if [ "$got" != "$want" ]; then
		echo "sha256 mismatch for $name: got $got want $want" >&2
		rm -f "$dl/$name"
		return 1
	fi
	echo "sha256 ok  $name"
	case $name in
	*.zip) unzip -q -o "$dl/$name" -d "$WORK/bin/$variant" ;;
	*.tar.gz) tar -xzf "$dl/$name" -C "$WORK/bin/$variant" ;;
	esac
	chmod +x "$bin"
}

cmd_fetch() {
	log "fetch $VERSION (sha256 from SHA256SUMS)"
	fetch_asset opencode-darwin-arm64.zip
	for v in linux-arm64 linux-arm64-musl linux-x64 linux-x64-baseline \
		linux-x64-musl linux-x64-baseline-musl; do
		fetch_asset "opencode-$v.tar.gz"
	done
}

# Real $HOME paths OpenCode would use by default; they must not appear.
home_paths() {
	for p in .config/opencode .local/share/opencode .local/state/opencode \
		.cache/opencode .opencode "Library/Application Support/opencode" \
		Library/Caches/opencode; do
		printf '%s\n' "$HOME/$p"
	done
	printf '%s\n' "${TMPDIR:-/tmp}/opencode"
}

cmd_macos() {
	log "macOS $(uname -m) $(sw_vers -productVersion 2>/dev/null || true)"
	before=$(home_paths | while read -r p; do [ -e "$p" ] && echo "$p"; done || true)
	out="$WORK/out/macos-$(uname -m)"
	rm -rf "$out"
	sh "$here/probe.sh" "$WORK/bin/darwin-arm64/opencode" "$out" "$here" | tee "$out.txt"
	after=$(home_paths | while read -r p; do [ -e "$p" ] && echo "$p"; done || true)
	{
		echo
		echo "## real \$HOME and system TMPDIR"
		if [ "$before" = "$after" ]; then
			echo "unchanged (checked: $(home_paths | tr '\n' ' '))"
		else
			echo "CHANGED"
			echo "before: $before"
			echo "after:  $after"
		fi
	} | tee -a "$out.txt"
}

# Host packages each image needs before OpenCode can start. Alpine: the musl
# builds link libstdc++/libgcc dynamically (not in the base image).
prep_for() {
	case $1 in
	alpine*) echo 'apk add --no-cache -q libstdc++ libgcc >/dev/null &&' ;;
	*) echo '' ;;
	esac
}

# docker_probe <image> <platform> <variant>: run probe.sh in a container.
docker_probe() {
	image=$1
	plat=$2
	variant=$3
	tag=$(printf '%s-%s-%s' "$image" "$plat" "$variant" | tr ':/' '__')
	out="$WORK/out/$tag"
	rm -rf "$out"
	mkdir -p "$out"
	log "docker $image ($plat) variant=$variant prep='$(prep_for "$image")'"
	docker run --rm --platform "$plat" \
		-v "$here:/spike:ro" \
		-v "$WORK/bin/$variant:/oc:ro" \
		-v "$out:/out" \
		"$image" sh -c "$(prep_for "$image") sh /spike/probe.sh /oc/opencode /out /spike" |
		tee "$out.txt" || true
}

cmd_linux() {
	for image in $IMAGES; do
		case $image in
		alpine*) libc=musl ;;
		*) libc=glibc ;;
		esac
		for plat in linux/arm64 linux/amd64; do
			case "$plat/$libc" in
			linux/arm64/glibc) variant=linux-arm64 ;;
			linux/arm64/musl) variant=linux-arm64-musl ;;
			# qemu amd64 in this VM has no AVX2 -> baseline (rule in RESULTS.md).
			linux/amd64/glibc) variant=linux-x64-baseline ;;
			linux/amd64/musl) variant=linux-x64-baseline-musl ;;
			esac
			docker_probe "$image" "$plat" "$variant"
		done
	done
}

# The qemu x86_64 CPU here has no AVX/AVX2 (TCG): run the full probe with the
# normal (AVX2) build too, to see whether it fails beyond --version.
cmd_noavx2() {
	docker_probe ubuntu:22.04 linux/amd64 linux-x64
}

# variant_row <image> <platform> <variant> <prep> <label>
variant_row() {
	res=$(docker run --rm --platform "$2" -v "$WORK/bin/$3:/oc:ro" "$1" \
		sh -c "$4 timeout -s KILL 300 /oc/opencode --version 2>&1; echo \"exit=\$?\"" 2>&1 |
		grep -v -E '^(Unable to find|[0-9a-f]+: |Digest:|Status:|.*Pulling)' |
		tail -2 | tr '\n' ' ') || true
	printf '%-22s %-12s %-26s %s\n' "$5" "$2" "$3" "$res"
}

# Start every Linux variant on every image/arch and record whether
# `opencode --version` works.
cmd_variants() {
	log "variant matrix ($VERSION)"
	printf '%-22s %-12s %-26s %s\n' IMAGE PLATFORM VARIANT RESULT
	for image in $VARIANT_IMAGES; do
		real=${image%%+*}
		prep=''
		case $image in
		*+libstdc++) prep=$(prep_for "$real") ;;
		esac
		for plat in linux/amd64 linux/arm64; do
			case $plat in
			linux/amd64) vs="linux-x64 linux-x64-baseline linux-x64-musl linux-x64-baseline-musl" ;;
			linux/arm64) vs="linux-arm64 linux-arm64-musl" ;;
			esac
			for v in $vs; do
				variant_row "$real" "$plat" "$v" "$prep" "$image"
			done
		done
	done
}

# Missing TMPDIR behaviour per variant (macOS host + one image per libc).
cmd_tmpdir() {
	log "tmpdir darwin-arm64 (host)"
	sh "$here/tmpdir-check.sh" "$WORK/bin/darwin-arm64/opencode"
	for spec in ubuntu:22.04,linux/arm64,linux-arm64 ubuntu:22.04,linux/amd64,linux-x64-baseline \
		alpine:3.20,linux/arm64,linux-arm64-musl alpine:3.20,linux/amd64,linux-x64-baseline-musl; do
		image=${spec%%,*}
		rest=${spec#*,}
		plat=${rest%%,*}
		v=${rest#*,}
		log "tmpdir $image ($plat) $v"
		docker run --rm --platform "$plat" -v "$here:/spike:ro" -v "$WORK/bin/$v:/oc:ro" \
			"$image" sh -c "$(prep_for "$image") sh /spike/tmpdir-check.sh /oc/opencode" 2>&1 || true
	done
}

case ${1:-} in
fetch) cmd_fetch ;;
tmpdir) cmd_tmpdir ;;
macos) cmd_macos ;;
linux) cmd_linux ;;
variants) cmd_variants ;;
noavx2) cmd_noavx2 ;;
all)
	cmd_fetch
	cmd_macos
	cmd_linux
	cmd_noavx2
	cmd_variants
	cmd_tmpdir
	;;
*)
	sed -n '2,19p' "$0"
	exit 2
	;;
esac
