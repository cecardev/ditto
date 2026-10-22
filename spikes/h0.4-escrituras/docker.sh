#!/bin/sh
# Spike H0.4 — Linux driver. Runs run.sh in a throwaway Ubuntu 22.04
# container as a clean non-root user (dev, uid 1000, empty HOME). The
# snapshot covers the whole container filesystem (-xdev), the session runs
# under strace -f -e trace=file (arm64; ptrace does not work under qemu-user)
# and inotifywait watches /tmp, /var/tmp, $HOME and XDG_RUNTIME_DIR, which is
# set as a systemd login would (/run/user/1000). Only logs, outputs and
# snapshots are copied out (docker cp).
#
#   sh docker.sh <work-dir> [arm64|amd64] [full|opencode]
#
# Host prerequisites baked into the image (arch.md §1, category B): git,
# openssh-client, curl, unzip, CA certificates; plus strace/inotify-tools
# (spike tooling only). amd64 on an arm64 host runs emulated.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
[ $# -ge 1 ] || { echo "usage: $0 <work-dir> [arm64|amd64] [full|opencode]" >&2; exit 2; }
mkdir -p "$1"
WORK=$(cd "$1" && pwd -P)
ARCH=${2:-arm64}
PROFILE=${3:-full}
TAG="ditto-h04-ubuntu-22.04-$ARCH"
STRACE=1
[ "$ARCH" = amd64 ] && STRACE=0
printf '%s\n' 'FROM ubuntu:22.04' \
	'RUN apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates curl git openssh-client zsh unzip strace inotify-tools >/dev/null && rm -rf /var/lib/apt/lists/*' \
	'RUN useradd -M -u 1000 -s /bin/bash dev && mkdir -p /home/dev /w /r /run/user/1000 && chown dev:dev /home/dev /w /r /run/user/1000 && chmod 0700 /run/user/1000' |
	docker build -q --platform "linux/$ARCH" -t "$TAG" - >/dev/null || exit 1

echo "== ubuntu-22.04 linux/$ARCH ($PROFILE)" >&2
NAME="$TAG-$$"
docker run --name "$NAME" --platform "linux/$ARCH" --cap-add SYS_PTRACE --user dev \
	-e HOME=/home/dev -e USER=dev -e LANG=C.UTF-8 -e DITTO_SPIKE_DISPOSABLE_HOME=1 \
	-e H04_WS=/w -e H04_SNAP_ROOTS=root=/ -e H04_SNAP_PRUNE=/spikes \
	-e H04_PTY_ENV_EXTRA=XDG_RUNTIME_DIR=/run/user/1000 -e H04_STRACE="$STRACE" \
	-e H04_INOTIFY="/tmp /var/tmp /home/dev /run/user/1000" \
	-e H04_PHASES="${H04_PHASES:-A B}" -e H04_OC_RUN="${H04_OC_RUN:-1}" \
	-v "$HERE/..:/spikes:ro" "$TAG" \
	sh /spikes/h0.4-escrituras/run.sh /r "$PROFILE"
rc=$?
for _d in logs out snap; do
	rm -rf "${WORK:?}/$_d"
	docker cp -q "$NAME:/r/$_d" "$WORK/$_d"
done
docker rm -f "$NAME" >/dev/null
exit "$rc"
