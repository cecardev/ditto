#!/bin/sh
# Spike H0.1b — Linux driver. Runs run.sh in a container with bash, zsh, git
# and an ssh client, and an ~/.ssh/config fixture in the passwd home (/root):
# ssh ignores $HOME, so the scenarios' HOMEs under <work-dir> do not hide it.
#
#   sh docker.sh <ubuntu-18.04|ubuntu-22.04|debian-12> <amd64|arm64> <work-dir>
#
# amd64 on an arm64 host runs emulated (--platform linux/amd64). The
# containers run as root: on a Linux docker host <work-dir> ends up owned by
# root (remove it with `docker run --rm -v <work-dir>:/w alpine rm -rf /w/dest`).
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
SPIKES=$(cd "$HERE/.." && pwd -P)
[ $# -eq 3 ] || { echo "usage: $0 <image-key> <amd64|arm64> <work-dir>" >&2; exit 2; }
KEY=$1 ARCH=$2
mkdir -p "$3"
WORK=$(cd "$3" && pwd -P)

case "$KEY" in
ubuntu-18.04 | ubuntu-20.04 | ubuntu-22.04 | debian-12) IMAGE=$(echo "$KEY" | sed 's/-/:/') ;;
*) echo "unknown image key: $KEY" >&2; exit 2 ;;
esac
PREREQ="apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates curl git openssh-client zsh >/dev/null"
SSH_FIXTURE="mkdir -p /root/.ssh && printf 'Host ditto-fixture\\n  User ditto-fixture-ssh\\n' > /root/.ssh/config && chmod 600 /root/.ssh/config"

TAG="ditto-h01b-$KEY-$ARCH"
printf 'FROM %s\nRUN %s\nRUN %s\n' "$IMAGE" "$PREREQ" "$SSH_FIXTURE" |
	docker build -q --platform "linux/$ARCH" -t "$TAG" - >/dev/null || exit 1

# MISE_* as a host user with mise would have them exported in the shell that
# runs ditto: the isolation must drop them.
echo "== $KEY linux/$ARCH ($IMAGE)" >&2

docker run --rm --platform "linux/$ARCH" -e DITTO_SPIKE_SSH_FIXTURE=1 -e DITTO_SPIKE_DISPOSABLE_HOME=1 \
	-e MISE_DATA_DIR=/root/host-mise -e MISE_ENV=host -e MISE_SHIMS_DIR=/root/host-mise/shims \
	-v "$SPIKES:/spikes:ro" -v "$WORK:/work" "$TAG" \
	sh /spikes/h0.1b-mise-sesion/run.sh /work/dest
