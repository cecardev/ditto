#!/bin/sh
# Spike H0.1 — Linux driver. Runs run.sh inside a container: the online phase
# with network (and a fake host mise in the container's $HOME), then the
# offline phase in a fresh container with --network none on the same volume.
#
#   sh docker.sh <ubuntu-18.04|ubuntu-22.04|alpine-3.20|debian-12|rocky-8> <amd64|arm64> <work-dir>
#
# amd64 on an arm64 host runs emulated (--platform linux/amd64).
#
# The containers run as root (HOME=/root is the disposable home of test 8;
# --user would leave HOME unwritable). On a Linux docker host the files in
# <work-dir> therefore end up owned by root: remove them with
# `docker run --rm -v <work-dir>:/w alpine rm -rf /w/ws` or sudo. With
# colima/Docker Desktop on macOS, paths outside the shared mounts (e.g.
# /private/tmp under colima) live only inside the VM.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
[ $# -eq 3 ] || { echo "usage: $0 <image-key> <amd64|arm64> <work-dir>" >&2; exit 2; }
KEY=$1 ARCH=$2
mkdir -p "$3"
WORK=$(cd "$3" && pwd -P)

# Host prerequisites the spike assumes (arch.md §1, category B): an HTTPS
# client and CA certificates. Installed before the marker, so not counted.
case "$KEY" in
ubuntu-18.04 | ubuntu-20.04 | ubuntu-22.04 | debian-12)
	IMAGE=$(echo "$KEY" | sed 's/-/:/')
	PREREQ="apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates curl >/dev/null"
	;;
rocky-8)
	IMAGE=rockylinux:8
	# findutils is needed by run.sh itself (test 7), not by mise.
	PREREQ="dnf install -y -q findutils >/dev/null"
	;;
alpine-3.20)
	IMAGE=alpine:3.20
	# OpenCode's -musl build links libstdc++/libgcc_s dynamically; without
	# them it fails with "Error loading shared library libstdc++.so.6".
	# DITTO_SPIKE_ALPINE_BARE=1 skips them to reproduce that failure.
	if [ "${DITTO_SPIKE_ALPINE_BARE:-0}" = 1 ]; then
		PREREQ="true"
	else
		PREREQ="apk add --no-cache -q libstdc++ libgcc"
	fi
	;;
*) echo "unknown image key: $KEY" >&2; exit 2 ;;
esac

# Bake the prerequisites into a local image so the offline container (no
# network) has them too.
TAG="ditto-h01-$KEY-$ARCH"
[ "${DITTO_SPIKE_ALPINE_BARE:-0}" = 1 ] && TAG="$TAG-bare"
printf 'FROM %s\nRUN %s\n' "$IMAGE" "$PREREQ" |
	docker build -q --platform "linux/$ARCH" -t "$TAG" - >/dev/null || exit 1

# MISE_* as a host user with mise would have them exported: the isolation
# must drop them (otherwise T2/T7 fail: data in /root/host-mise, env "host").
HOST_MISE_ENV="-e MISE_DATA_DIR=/root/host-mise -e MISE_CACHE_DIR=/root/host-mise/cache -e MISE_ENV=host -e MISE_SHIMS_DIR=/root/host-mise/shims"

echo "== $KEY linux/$ARCH ($IMAGE): online" >&2
# shellcheck disable=SC2086 # HOST_MISE_ENV is a list of flags
docker run --rm --platform "linux/$ARCH" -e DITTO_SPIKE_HOST_MISE=1 -e DITTO_SPIKE_DISPOSABLE_HOME=1 \
	$HOST_MISE_ENV -v "$HERE:/spike:ro" -v "$WORK:/work" "$TAG" \
	sh /spike/run.sh /work/ws online
rc1=$?

echo "== $KEY linux/$ARCH ($IMAGE): offline (--network none)" >&2
# shellcheck disable=SC2086
docker run --rm --platform "linux/$ARCH" --network none \
	$HOST_MISE_ENV -v "$HERE:/spike:ro" -v "$WORK:/work" "$TAG" \
	sh /spike/run.sh /work/ws offline
rc2=$?

[ "$rc1" = 0 ] && [ "$rc2" = 0 ]
