#!/bin/sh
# Spike H0.4 — the OpenCode part of the session script, typed in the session
# shell (so `opencode` is the .ditto/bin wrapper). cwd = the project repo,
# whose opencode.json declares two fake local MCPs (sh and npx) and denies
# every tool (bash, edit, webfetch): the agent can only answer with text.
#
#   sh oc-session.sh <out-dir> <tag>
#
# No credentials are used. `opencode run` (a prompt sent to OpenCode Zen with
# a free model listed by `opencode models`) is OPT-IN: only with H04_OC_RUN=1.
# Writes <out>/<tag>-opencode.log and <out>/<tag>-oc.done.
set -u
out=$1
tag=$2
log="$out/$tag-opencode.log"
: >"$log"

# run_t <secs> <cmd...> — portable timeout (macOS has no timeout(1)).
run_t() {
	_secs=$1
	shift
	"$@" &
	_pid=$!
	(sleep "$_secs" && kill "$_pid" 2>/dev/null && sleep 5 && kill -9 "$_pid" 2>/dev/null) &
	_w=$!
	wait "$_pid"
	_rc=$?
	kill "$_w" 2>/dev/null
	wait "$_w" 2>/dev/null
	return "$_rc"
}

oc() { # <secs> <args...>
	_t=$1
	shift
	{
		echo "\$ opencode $*"
		run_t "$_t" opencode "$@" 2>&1 </dev/null
		echo "exit=$?"
	} >>"$log"
}

oc 60 --version
oc 60 debug paths
echo "\$ opencode models" >>"$log"
run_t 180 opencode models >"$out/$tag-models.txt" 2>&1 </dev/null
echo "exit=$? ($(wc -l <"$out/$tag-models.txt" | tr -d ' ') lines in $tag-models.txt)" >>"$log"
oc 120 mcp list
oc 8 serve --port 0 --hostname 127.0.0.1
# Free models come and go (a free model may answer with a server error):
# try up to three, stop at the first success.
models=$(grep -E '^opencode/[^ ]*free' "$out/$tag-models.txt" | head -n 3 || true)
if [ "${H04_OC_RUN:-0}" = 1 ] && [ -n "$models" ]; then
	for model in $models; do
		echo "# short request with free model $model (no credentials)" >>"$log"
		oc 180 run -m "$model" "Responde solo con la palabra: ok"
		tail -n 1 "$log" | grep -q '^exit=0$' && break
	done
else
	echo "# opencode run skipped (opt-in: H04_OC_RUN=${H04_OC_RUN:-0})" >>"$log"
fi
oc 60 session list
: >"$out/$tag-oc.done"
