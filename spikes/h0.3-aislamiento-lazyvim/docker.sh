#!/bin/sh
# Spike H0.3 — Linux driver. Runs run.sh in a throwaway container: HOME=/root
# and /tmp are the container's own, the workspace lives in the container
# (/h03, a short path), and only the logs and probe outputs are copied out.
#
#   sh docker.sh <work-dir> [arm64|amd64] [ubuntu-22.04|ubuntu-18.04|debian-12]
#
# Host prerequisites baked into the image (arch.md §1, category B): git,
# openssh-client, curl, CA certificates; bash is in the base image and zsh is
# added to test it too. amd64 on an arm64 host runs emulated.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
[ $# -ge 1 ] || { echo "usage: $0 <work-dir> [arm64|amd64] [ubuntu-22.04|ubuntu-18.04|debian-12]" >&2; exit 2; }
mkdir -p "$1"
WORK=$(cd "$1" && pwd -P)
ARCH=${2:-arm64}
KEY=${3:-ubuntu-22.04}
case "$KEY" in
ubuntu-18.04 | ubuntu-22.04 | debian-12) IMAGE=$(echo "$KEY" | sed 's/-/:/') ;;
*) echo "unknown image key: $KEY" >&2; exit 2 ;;
esac
TAG="ditto-h03-$KEY-$ARCH"
# The image's skeleton /root/.bashrc is removed so HOME=/root starts empty of
# user rc files: run.sh refuses to overwrite existing ones.
printf 'FROM %s\nRUN apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates curl git openssh-client zsh >/dev/null && rm -rf /var/lib/apt/lists/* && rm -f /root/.bashrc\n' "$IMAGE" |
	docker build -q --platform "linux/$ARCH" -t "$TAG" - >/dev/null || exit 1

echo "== $KEY linux/$ARCH ($IMAGE)" >&2
# Results are copied out with `docker cp` (no bind mount for them): with
# colima/Docker Desktop only some host paths are shared with the VM.
NAME="$TAG-$$"
docker run --name "$NAME" --platform "linux/$ARCH" -e DITTO_SPIKE_DISPOSABLE_HOME=1 \
	-e H03_SHELLS="${H03_SHELLS:-bash zsh}" -e H03_SCENARIOS="${H03_SCENARIOS:-A B}" \
	-e H03_GIT_MODES="${H03_GIT_MODES:-none global include symlink}" \
	-v "$HERE/..:/spikes:ro" "$TAG" \
	sh /spikes/h0.3-aislamiento-lazyvim/run.sh /h03
rc=$?
rm -rf "$WORK/logs" "$WORK/out"
docker cp -q "$NAME:/h03/logs" "$WORK/logs"
docker cp -q "$NAME:/h03/out" "$WORK/out"
docker rm -f "$NAME" >/dev/null
exit "$rc"
