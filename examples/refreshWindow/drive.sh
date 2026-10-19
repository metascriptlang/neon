#!/bin/bash
# Drives Neon Refresh over MetaScript HCR in a real Ion window on Windows: real clicks and keystrokes
# (win.ps1), a template edit and a setup edit, each checked through the app's log, with a screenshot
# after each step. Pristine sources are copied into <repo>/out/refreshWindow and the edits land there.
# usage: examples/refreshWindow/drive.sh
SRC=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SRC/../.." && pwd)
WORK=$ROOT/out/refreshWindow
LOG=$WORK/dev.log
WIN="powershell -NoProfile -ExecutionPolicy Bypass -File $(cygpath -w "$SRC/win.ps1")"
FAILED=0
SEEN=0

now() { date +%s%3N; }
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILED=1; }
check() { if [ "$2" = "$3" ]; then pass "$1: $2"; else fail "$1: got '$2', expected '$3'"; fi; }
next() {
	local deadline=$(($(now) + $2 * 1000)) n
	while [ $(now) -lt $deadline ]; do
		n=$(tail -n +$((SEEN + 1)) "$LOG" | grep -n -m1 -E "$1")
		if [ -n "$n" ]; then
			SEEN=$((SEEN + ${n%%:*}))
			LINE=${n#*:}
			return 0
		fi
		sleep 0.1
	done
	LINE=""
	return 1
}
since() { tail -n +$((SEEN + 1)) "$LOG" | grep -E "$1"; }
mark() { SEEN=$(wc -l < "$LOG"); }
win() { $WIN "$@"; }
shot() { win shot "$(cygpath -w "$WORK/$1.png")"; echo "shot $WORK/$1.png"; }
press() { mark; win click 104 144; sleep 0.4; since "^RW press" | tr '\n' ';'; }
edit() { mark; T0=$(now); sed -i "$2" "$WORK/$1"; }
reloaded() {
	next "^HCR [a-z ]+ \[" 60 || { fail "$1: no answer from the engine"; return 1; }
	case "$LINE" in "HCR reloaded"*) echo "timing $1: edit to reloaded $(($(now) - T0)) ms (poll included)" ;; *) fail "$1: $LINE"; return 1 ;; esac
	sleep 0.5
}

mkdir -p "$WORK"
rm -f "$WORK"/*.png
for f in build.ms app.ms counter.ms; do cp "$SRC/$f" "$WORK/$f"; done
(cd "$WORK" && exec msc run --hcr app.ms) > "$LOG" 2>&1 &
DEV=$!
trap 'win close > /dev/null 2>&1; sleep 1; kill $DEV 2> /dev/null' EXIT
next "^RW layout" 300 || { tail -20 "$LOG"; fail "the window did not lay out"; exit 1; }
sleep 1
win find

check "first press" "$(press)" "RW press count=1;"
press > /dev/null; press > /dev/null
check "third press" "$(grep "^RW press" "$LOG" | tail -1)" "RW press count=3"
shot s0

edit counter.ms "s/>Counter v1</>Counter v2</"
reloaded "template edit"
shot s1
check "template edit keeps the count and leaves one handler" "$(press)" "RW press count=4;"

mark; win click 144 218; sleep 0.3; win type typed; sleep 0.5
check "typing reaches the field" "$(since '^RW text' | tail -1)" 'RW text "typed"'

edit counter.ms "s/count() + 1/count() + 2/"
reloaded "setup edit"
mark; win type X; sleep 0.5
check "setup edit keeps the typed text and the focus" "$(since '^RW text' | tail -1)" 'RW text "typedX"'
check "setup edit runs the new handler, count kept" "$(press)" "RW press count=6;"
shot s2

[ $FAILED = 0 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; tail -30 "$LOG"; }
exit $FAILED
