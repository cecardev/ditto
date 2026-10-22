#!/bin/sh
# tmpdir-check.sh <opencode-bin>: does OpenCode start when TMPDIR is missing?
# Found while probing: the linux-x64 builds abort (core dump) under qemu,
# arm64 and macOS create it. ditto must create .ditto/tmp before exec.
set -u
OC=$1
sandbox=$(mktemp -d)
mkdir -p "$sandbox/home" "$sandbox/exists"
for t in "$sandbox/exists" "$sandbox/missing"; do
	echo "== TMPDIR=${t#"$sandbox"/} opencode debug paths"
	env -i PATH=/usr/bin:/bin HOME="$sandbox/home" TMPDIR="$t" "$OC" debug paths 2>&1 | tail -1
done
rm -rf "$sandbox"
