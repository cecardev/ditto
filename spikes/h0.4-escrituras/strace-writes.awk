# Spike H0.4 — write-like file syscalls from `strace -f -qq -y -e
# trace=file,fchdir,clone,clone3,fork,vfork`, as absolute paths.
#
#   awk -v start=<cwd of the traced root> -v dest=<dest>/ -v ditto=<ws>/.ditto/ -f strace-writes.awk <log>
#
# Relative names are resolved against the decoded dirfd (`-y`: 17</dir>) or,
# for AT_FDCWD, against the cwd of the process, tracked through chdir/fchdir
# and inherited on clone/fork. Prints "<syscall>\t<path>" for successful calls
# outside <dest> and .ditto (and outside /proc, /dev, /sys), one per line.

function join(dir, rel) {
	if (rel ~ /^\//) return rel
	if (dir == "") dir = start
	sub(/\/$/, "", dir)
	return dir "/" rel
}

function cwdof(p) {
	return (p in cwd) ? cwd[p] : start
}

{
	pid = $1
	line = $0
	sub(/^[0-9]+ +/, "", line)
}

# Children inherit the cwd (clone returns the child pid in the parent). With
# vfork/CLONE_VFORK the child may run (and chdir) before the parent's line is
# printed: never overwrite a cwd the child already set.
line ~ /^(<\.\.\. )?(clone|clone3|fork|vfork)[ (]/ && match(line, /= [0-9]+$/) {
	c = substr(line, RSTART + 2)
	if (!(c in cwd)) cwd[c] = cwdof(pid)
	next
}

line ~ / = -1 / || line ~ /<unfinished \.\.\.>$/ { next }

line ~ /^chdir\("/ {
	split(line, q, "\"")
	cwd[pid] = join(cwdof(pid), q[2])
	next
}

line ~ /^fchdir\([0-9]+</ {
	d = line
	sub(/^fchdir\([0-9]+</, "", d)
	sub(/>.*/, "", d)
	cwd[pid] = d
	next
}

{
	sc = line
	sub(/\(.*/, "", sc)
	if (sc !~ /^(open|openat|openat2|creat|mkdir|mkdirat|rename|renameat|renameat2|unlink|unlinkat|rmdir|symlink|symlinkat|link|linkat|truncate|utimensat|utimes|chmod|fchmodat|mknod|mknodat)$/) next
	if (sc ~ /^(open|openat|openat2)$/ && line !~ /O_WRONLY|O_RDWR|O_CREAT|O_TRUNC/) next
	args = line
	sub(/^[a-z0-9]+\(/, "", args)
	ctx = "cwd"
	nstr = 0
	# Scan tokens left to right: decoded dirfds, AT_FDCWD and strings.
	# With -y strace prints AT_FDCWD</cwd> itself; the tracked cwd is only a
	# fallback for the syscalls without a dirfd (open, mkdir, unlink...).
	while (match(args, /AT_FDCWD<[^>]*>|[0-9]+<[^>]*>|AT_FDCWD|"[^"]*"/)) {
		tok = substr(args, RSTART, RLENGTH)
		args = substr(args, RSTART + RLENGTH)
		if (tok == "AT_FDCWD") { ctx = "cwd"; continue }
		if (tok ~ /^(AT_FDCWD|[0-9]+)</) { d = tok; sub(/^[^<]*</, "", d); sub(/>$/, "", d); ctx = d; continue }
		nstr++
		s = substr(tok, 2, length(tok) - 2)
		# symlink(at): the first string is the link target, not a path written.
		if (sc ~ /^symlink/ && nstr == 1) continue
		p = join(ctx == "cwd" ? cwdof(pid) : ctx, s)
		ctx = "cwd"
		if (index(p, dest) == 1 || index(p, ditto) == 1) continue
		if (p ~ /^\/(proc|dev|sys)(\/|$)/) continue
		print sc "\t" p
	}
}
