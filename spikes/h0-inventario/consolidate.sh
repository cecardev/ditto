#!/bin/sh
# consolidate.sh - build the host x binary table from inventory files.
#
# Usage: consolidate.sh FILE.txt...
# Prints Markdown to stdout:
#   1. host x field table (system + version of each binary)
#   2. checks against arch.md section 1 (hard prerequisites, min_version)
#   3. summary (lowest glibc, how many hosts satisfy each min_version)
set -eu

if [ $# -eq 0 ]; then
	echo "usage: consolidate.sh FILE.txt..." >&2
	exit 2
fi

awk '
function trim_val(s) {
	sub(/^[^=]*=[ ]*/, "", s)
	gsub(/^"|"$/, "", s)
	return s
}
# vcmp(a, b): -1, 0, 1 comparing dotted versions numerically.
function vcmp(a, b,    na, nb, pa, pb, i, n, x, y) {
	na = split(a, pa, ".")
	nb = split(b, pb, ".")
	n = na > nb ? na : nb
	for (i = 1; i <= n; i++) {
		x = (i <= na) ? pa[i] + 0 : 0
		y = (i <= nb) ? pb[i] + 0 : 0
		if (x < y) return -1
		if (x > y) return 1
	}
	return 0
}
function cell(h, k,    v) {
	if (!((h, k, "found") in d)) return "?"
	if (d[h, k, "found"] == "false") return "—"
	v = d[h, k, "version"]
	return v == "" ? "sí (sin versión)" : v
}
function sys(h, k,    v) {
	v = d[h, "host", k]
	return v == "" ? "—" : v
}
FNR == 1 {
	nh++
	host[nh] = FILENAME
	sec = ""
}
/^\[/ {
	sec = $0
	gsub(/^\[|\]$/, "", sec)
	next
}
/^[a-z_0-9]+ = / {
	key = $1
	val = trim_val($0)
	h = host[nh]
	if (sec == "host") {
		d[h, "host", key] = val
		if (key == "label") label[nh] = val
	} else if (sec ~ /^bin\./) {
		b = substr(sec, 5)
		if (!(b in seen)) { seen[b] = 1; nb++; bins[nb] = b }
		d[h, b, key] = val
	}
}
END {
	# 1. Table host x field.
	printf "| Campo |"
	for (i = 1; i <= nh; i++) printf " %s |", label[i]
	printf "\n|---|"
	for (i = 1; i <= nh; i++) printf "---|"
	printf "\n"
	ns = split("in_container os arch distro_id distro_version macos_version libc libc_version avx2 cpu_count", sk, " ")
	for (j = 1; j <= ns; j++) {
		printf "| %s |", sk[j]
		for (i = 1; i <= nh; i++) printf " %s |", sys(host[i], sk[j])
		printf "\n"
	}
	for (j = 1; j <= nb; j++) {
		b = bins[j]
		cat = ""
		for (i = 1; i <= nh && cat == ""; i++) cat = d[host[i], b, "category"]
		printf "| `%s` (%s) |", b, cat
		for (i = 1; i <= nh; i++) printf " %s |", cell(host[i], b)
		printf "\n"
	}

	# 2. Checks (thresholds from arch.md section 1).
	nm = split("git:2.19 nvim:0.11.2 node:18 python3:3.9", mins, " ")
	printf "\n### Comprobaciones (umbrales de arch.md §1)\n\n"
	printf "| Comprobación |"
	for (i = 1; i <= nh; i++) printf " %s |", label[i]
	printf "\n|---|"
	for (i = 1; i <= nh; i++) printf "---|"
	printf "\n"
	printf "| duros: `git` ≥ 2.19, `curl`/`wget`, `tar`, `unzip` |"
	for (i = 1; i <= nh; i++) {
		h = host[i]; miss = ""
		if (d[h, "git", "found"] != "true") miss = miss " git"
		else if (vcmp(d[h, "git", "version"], "2.19") < 0) miss = miss " git<2.19"
		if (d[h, "curl", "found"] != "true" && d[h, "wget", "found"] != "true") miss = miss " curl/wget"
		if (d[h, "tar", "found"] != "true") miss = miss " tar"
		if (d[h, "unzip", "found"] != "true") miss = miss " unzip"
		printf " %s |", (miss == "" ? "ok" : "FALTA:" miss)
	}
	printf "\n| blandos: `cc`, `ssh` |"
	for (i = 1; i <= nh; i++) {
		h = host[i]; miss = ""
		if (d[h, "cc", "found"] != "true") miss = miss " cc"
		if (d[h, "ssh", "found"] != "true") miss = miss " ssh"
		printf " %s |", (miss == "" ? "ok" : "aviso:" miss)
	}
	printf "\n"
	for (m = 1; m <= nm; m++) {
		split(mins[m], mv, ":")
		printf "| `%s` ≥ %s en el host |", mv[1], mv[2]
		for (i = 1; i <= nh; i++) {
			h = host[i]
			if (d[h, mv[1], "found"] != "true") r = "no (ausente)"
			else if (d[h, mv[1], "version"] == "") r = "?"
			else if (vcmp(d[h, mv[1], "version"], mv[2]) >= 0) { r = "sí"; ok[m]++ }
			else r = "no (" d[h, mv[1], "version"] ")"
			printf " %s |", r
		}
		printf "\n"
	}

	# 3. Summary.
	minglibc = ""
	for (i = 1; i <= nh; i++) {
		h = host[i]
		if (d[h, "host", "libc"] == "glibc" && d[h, "host", "libc_version"] != "")
			if (minglibc == "" || vcmp(d[h, "host", "libc_version"], minglibc) < 0) {
				minglibc = d[h, "host", "libc_version"]; minhost = label[i]
			}
		if (d[h, "host", "libc"] == "musl") musl = musl " " label[i]
		if (d[h, "host", "avx2"] == "no") noavx = noavx " " label[i]
	}
	printf "\n### Resumen\n\n"
	if (minglibc == "") printf "- glibc mínima: — (ningún host glibc)\n"
	else {
		printf "- glibc mínima: **%s** (%s)", minglibc, minhost
		if (vcmp(minglibc, "2.31") < 0) printf " → < 2.31: el fallback legacy de Neovim (§7) es obligatorio"
		printf "\n"
	}
	printf "- hosts musl: %s\n", (musl == "" ? "ninguno" : musl)
	printf "- hosts x86_64 sin AVX2: %s\n", (noavx == "" ? "ninguno" : noavx)
	for (m = 1; m <= nm; m++) {
		split(mins[m], mv, ":")
		printf "- `%s` ≥ %s: %d/%d hosts\n", mv[1], mv[2], ok[m] + 0, nh
	}
}
' "$@"
