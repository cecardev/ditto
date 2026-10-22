#!/bin/sh
# run.sh - reproducible driver for spike H0 inventory (issue #3).
#
#   ./run.sh local [LABEL]       inventory of this machine -> results/hosts/
#   ./run.sh docker [KEY...]     script validation in containers -> results/validation/
#   ./run.sh docker-pkgs [KEY...] same, with the tools installed -> results/validation-pkgs/
#   ./run.sh consolidate [DIR]   Markdown table from DIR (default results/hosts)
#
# Container runs are NOT real inventory: they only prove the script works
# with dash, busybox ash and bash, read-only and without network.
set -eu

here=$(cd "$(dirname "$0")" && pwd)

image_for() {
	case "$1" in
	ubuntu-18.04) echo ubuntu:18.04 ;;
	ubuntu-20.04) echo ubuntu:20.04 ;;
	ubuntu-22.04) echo ubuntu:22.04 ;;
	rocky-8) echo rockylinux:8 ;;
	debian-12) echo debian:12 ;;
	alpine-3.20) echo alpine:3.20 ;;
	*) return 1 ;;
	esac
}

cmd=${1:-}
[ $# -gt 0 ] && shift

case "$cmd" in
local)
	label=${1:-}
	if [ -n "$label" ]; then
		sh "$here/inventory.sh" -n "$label" -o "$here/results/hosts"
	else
		sh "$here/inventory.sh" -o "$here/results/hosts"
	fi
	;;
docker)
	[ $# -gt 0 ] || set -- ubuntu-18.04 ubuntu-22.04 alpine-3.20 rocky-8 debian-12
	platform=${DOCKER_PLATFORM:-}
	out="$here/results/validation"
	mkdir -p "$out"
	for key in "$@"; do
		img=$(image_for "$key") || {
			echo "unknown image key: $key" >&2
			exit 2
		}
		suffix=""
		if [ -n "$platform" ]; then
			suffix="-$(echo "$platform" | tr '/' '-')"
			set -- --platform "$platform"
		else
			set --
		fi
		# Read-only root fs and no network: the script must still work.
		# /bin/sh is dash (Debian/Ubuntu), busybox ash (Alpine), bash (Rocky).
		docker run --rm "$@" --network none --read-only \
			--user "$(id -u):$(id -g)" \
			-v "$here:/spike:ro" -v "$out:/out" \
			"$img" /bin/sh /spike/inventory.sh -n "ctr-$key$suffix" -o /out
	done
	;;
docker-pkgs)
	# Same validation, but first installs the probed tools from the distro
	# repos (needs network, inside the container only) so that the
	# "found = true" paths and version parsing are exercised.
	[ $# -gt 0 ] || set -- ubuntu-18.04 debian-12 alpine-3.20 rocky-8
	out="$here/results/validation-pkgs"
	mkdir -p "$out"
	for key in "$@"; do
		img=$(image_for "$key") || {
			echo "unknown image key: $key" >&2
			exit 2
		}
		# shellcheck disable=SC2016 # $p must expand inside the container
		case "$key" in
		ubuntu-* | debian-*)
			inst='export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null;
for p in git curl wget unzip xz-utils openssh-client gcc python3 zsh ripgrep fd-find fzf neovim nodejs golang-go; do
apt-get install -y -qq --no-install-recommends "$p" >/dev/null 2>&1 || echo "skip $p"; done' ;;
		alpine-*)
			inst='for p in git curl unzip xz openssh-client gcc python3 zsh bash ripgrep fd fzf lazygit neovim nodejs go; do
apk add -q "$p" >/dev/null 2>&1 || echo "skip $p"; done' ;;
		rocky-*)
			inst='for p in git curl wget unzip xz openssh-clients gcc python3 zsh nodejs golang; do
dnf install -y -q "$p" >/dev/null 2>&1 || echo "skip $p"; done' ;;
		esac
		docker run --rm -v "$here:/spike:ro" -v "$out:/out" "$img" /bin/sh -c \
			"$inst; SHELL=/bin/bash /bin/sh /spike/inventory.sh -n ctr-pkgs-$key -o /out; chown -R $(id -u):$(id -g) /out"
	done
	;;
consolidate)
	dir=${1:-$here/results/hosts}
	set -- "$dir"/*.txt
	[ -e "$1" ] || {
		echo "no .txt files in $dir" >&2
		exit 1
	}
	sh "$here/consolidate.sh" "$@"
	;;
*)
	sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
	;;
esac
