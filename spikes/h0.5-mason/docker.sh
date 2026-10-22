#!/bin/sh
# Spike H0.5 — Linux driver. Runs run.sh in a throwaway container: HOME=/root
# and /tmp are the container's own, the workspace is /h05 (short path) and
# only the logs are copied out. The container is removed afterwards; the image
# is kept until `docker.sh --clean`.
#
#   sh docker.sh <work-dir> [arm64|amd64] [ubuntu-18.04|ubuntu-22.04|rocky-8] [test|mise-lock-217]
#   sh docker.sh --clean          # remove the ditto-h05-* images
#
# Host prerequisites baked into the image (arch.md §1, category B): git, curl,
# CA certificates, unzip, tar/gzip/xz and a C compiler (nvim-treesitter
# builds the parsers with `tree-sitter build`, which calls cc). No node,
# python or go: the host has none, so only the mise runtimes exist.
# amd64 on an arm64 host runs emulated (slow: gopls is built from source).
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
if [ "${1:-}" = --clean ]; then
	docker images --format '{{.Repository}}' | grep '^ditto-h05-' | sort -u | while read -r _i; do
		docker rmi -f "$_i" >/dev/null && echo "removed $_i"
	done
	exit 0
fi
[ $# -ge 1 ] || { echo "usage: $0 <work-dir> [arm64|amd64] [ubuntu-18.04|ubuntu-22.04|rocky-8]" >&2; exit 2; }
mkdir -p "$1"
WORK=$(cd "$1" && pwd -P)
ARCH=${2:-arm64}
KEY=${3:-ubuntu-22.04}
case "$KEY" in
ubuntu-18.04 | ubuntu-22.04)
	IMAGE=$(echo "$KEY" | sed 's/-/:/')
	PREP='apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates curl git unzip xz-utils gcc libc6-dev >/dev/null && rm -rf /var/lib/apt/lists/* && rm -f /root/.bashrc /root/.profile'
	;;
rocky-8)
	IMAGE=rockylinux:8
	PREP='dnf install -y -q git unzip xz gcc tar gzip findutils diffutils >/dev/null && dnf clean all >/dev/null && rm -f /root/.bashrc /root/.bash_profile /root/.cshrc /root/.tcshrc'
	;;
*) echo "unknown image key: $KEY" >&2; exit 2 ;;
esac
TAG="ditto-h05-$KEY-$ARCH"
printf 'FROM %s\nRUN %s\n' "$IMAGE" "$PREP" |
	docker build -q --platform "linux/$ARCH" -t "$TAG" - >/dev/null || exit 1

echo "== $KEY linux/$ARCH ($IMAGE)" >&2
NAME="$TAG-$$"
docker run --name "$NAME" --platform "linux/$ARCH" -e DITTO_SPIKE_DISPOSABLE_HOME=1 \
	-e H05_CONTROL="${H05_CONTROL:-1}" -e H05_BASEDPYRIGHT="${H05_BASEDPYRIGHT:-1}" \
	-e H05_LSP_TIMEOUT="${H05_LSP_TIMEOUT:-240000}" ${H05_NODE_FLAVOR+-e H05_NODE_FLAVOR="$H05_NODE_FLAVOR"} \
	${GOMAXPROCS+-e GOMAXPROCS="$GOMAXPROCS"} \
	-v "$HERE/..:/spikes:ro" "$TAG" \
	sh /spikes/h0.5-mason/run.sh /h05 "${4:-test}"
rc=$?
rm -rf "${WORK:?}/logs"
docker cp -q "$NAME:/h05/logs" "$WORK/logs"
docker rm -f "$NAME" >/dev/null
exit "$rc"
