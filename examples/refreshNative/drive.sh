#!/bin/bash
# Runs the Neon Refresh native HCR scenarios. Pristine sources are copied into
# <repo>/out/refreshNative and every edit lands there, so tracked files stay untouched.
# usage: examples/refreshNative/drive.sh <main|parent> [log]
#   main:   s1 template-only, s3 repeated templates, s4 dependency, s5 compile error + fix, s2 setup edit
#   parent: s6 template edit of a component that mounts a child component (fresh session)
#   parentAfterChild: s1, then s6 (the child's module has been reloaded once)
SRC=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SRC/../.." && pwd)
WORK=$ROOT/out/refreshNative
STOP=$ROOT/out/refreshNative.stop
POKE=$ROOT/out/refreshNative.poke
STAGE=$ROOT/out/refreshNative.stage
PLAN=${1:-main}
LOG=${2:-$WORK.$PLAN.log}
mkdir -p "$WORK"
rm -f "$STOP" "$POKE"
for f in build.ms app.ms counter.ms panel.ms words.ms; do cp "$SRC/$f" "$WORK/$f"; done
: > "$LOG"
(cd "$WORK" && exec msc run --hcr app.ms) >> "$LOG" 2>&1 &
PID=$!

count() { grep -c -- "$1" "$LOG"; }
alive() { kill -0 $PID 2>/dev/null; }
baseline() { PAT=$1; ALT=${2:-}; N0=$(count "$PAT"); M0=0; [ -n "$ALT" ] && M0=$(count "$ALT"); }
waitPastBaseline() {
	for i in $(seq 1 $(($1 * 4))); do
		[ "$(count "$PAT")" -gt "$N0" ] && return 0
		[ -n "$ALT" ] && [ "$(count "$ALT")" -gt "$M0" ] && return 0
		alive || return 1
		sleep 0.25
	done
	return 1
}
step() { echo "=== DRIVE $1"; }
swap() { sleep 1; cp "$SRC/edits/$1" "$STAGE" && mv -f "$STAGE" "$WORK/$2"; }
edit() { # edit <label> <edit file> <target> [alt-pattern]
	step "$1: $2 -> $3"
	baseline "RN settled" "${4:-}"
	swap "$2" "$3"
	waitPastBaseline 120 || step "$1: TIMEOUT"
}

for i in $(seq 1 2400); do grep -q "RN ready" "$LOG" && break; alive || break; sleep 0.25; done
grep -q "RN ready" "$LOG" || { step "NO READY"; wait $PID; echo "exit $?" >> "$LOG"; exit 1; }

case $PLAN in
main)
	edit "s1 template-only" counter.s1.ms counter.ms
	edit "s3 template a" counter.s3a.ms counter.ms
	edit "s3 template b" counter.s3b.ms counter.ms
	edit "s4 dependency" words.s4.ms words.ms
	edit "s5 compile error" counter.s5bad.ms counter.ms "error"
	sleep 3; step "s5 poke while broken"; baseline "RN poke done"; touch "$POKE"; waitPastBaseline 30 || step "s5 poke TIMEOUT"
	edit "s5 fix" counter.s5fix.ms counter.ms
	edit "s2 setup" counter.s2setup.ms counter.ms
	;;
parent)
	edit "s6 parent template" panel.s6.ms panel.ms
	;;
parentAfterChild)
	edit "s1 template-only" counter.s1.ms counter.ms
	edit "s6 parent template" panel.s6.ms panel.ms
	;;
*) step "unknown plan $PLAN" ;;
esac
sleep 2; step "stop"; touch "$STOP"
wait $PID; echo "exit $?" >> "$LOG"
rm -f "$STOP" "$POKE"
