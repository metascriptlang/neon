#!/bin/bash
# Drives Neon Refresh over MetaScript HCR in a real Ion window on Windows: real clicks and keystrokes
# (win.ps1), a template edit and a setup edit, each checked through the app's log, with a screenshot
# after each step; then the same window through the devtools control channel and its event file
# (docs/DEVTOOLS.md). Pristine sources are copied into <repo>/out/refreshWindow and the edits land there.
# usage: examples/refreshWindow/drive.sh
SRC=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SRC/../.." && pwd)
WORK=$ROOT/out/refreshWindow
LOG=$WORK/dev.log
EVENTS=$WORK/events.jsonl
PORT=47341
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
rpc() {
	python -c 'import socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5)
s.sendall((sys.argv[2] + "\n").encode())
buf = b""
while not buf.endswith(b"\n"):
	buf += s.recv(65536)
print(buf.decode().strip())' "$PORT" "$1"
}
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1: '$3' not in $2" ;; esac; }
shot() { win shot "$(cygpath -w "$WORK/$1.png")"; echo "shot $WORK/$1.png"; }
press() { mark; win click 104 144; sleep 0.4; since "^RW press" | tr '\n' ';'; }
edit() { mark; T0=$(now); sed -i "$2" "$WORK/$1"; }
reloaded() {
	next "^HCR [a-z ]+ \[" 60 || { fail "$1: no answer from the engine"; return 1; }
	case "$LINE" in "HCR reloaded"*) echo "timing $1: edit to reloaded $(($(now) - T0)) ms (poll included)" ;; *) fail "$1: $LINE"; return 1 ;; esac
	sleep 0.5
}

mkdir -p "$WORK"
rm -f "$WORK"/*.png "$EVENTS"
for f in build.ms app.ms counter.ms; do cp "$SRC/$f" "$WORK/$f"; done
(cd "$WORK" && NEON_CONTROL=$PORT NEON_EVENTS=$(cygpath -w "$EVENTS") exec msc run --hcr app.ms) > "$LOG" 2>&1 &
DEV=$!
trap 'win close > /dev/null 2>&1; sleep 1; kill $DEV 2> /dev/null' EXIT
next "^RW layout" 300 || { tail -20 "$LOG"; fail "the window did not lay out"; exit 1; }
next "^neon devtools: control channel" 30 || { tail -20 "$LOG"; fail "the app never polled: no control channel"; exit 1; }
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
check "setup edit remounts the field: typed text and focus are lost until arc refresh-reuse lands" "$(since '^RW text' | tail -1)" ''
check "setup edit runs the new handler, count kept" "$(press)" "RW press count=6;"
shot s2

has "control: ping names the host" "$(rpc '{"jsonrpc":"2.0","id":1,"method":"ping"}')" '"result":{"protocol":1,"host":"Ion window"}'
has "control: the click on the button left the field unfocused" "$(rpc '{"jsonrpc":"2.0","id":2,"method":"tree"}')" '"id":"0.3","tag":"textinput","text":"","value":"","focused":false'
rpc '{"jsonrpc":"2.0","id":3,"method":"press","params":{"target":"0.3"}}' > /dev/null
has "control: press on the field by its id focuses it" "$(rpc '{"jsonrpc":"2.0","id":4,"method":"tree"}')" '"id":"0.3","tag":"textinput","text":"","value":"","focused":true'
has "control: components report the live kept count by its source name" "$(rpc '{"jsonrpc":"2.0","id":5,"method":"components"}')" '"component":"Counter","module":'
has "control: components report the live kept count" "$(rpc '{"jsonrpc":"2.0","id":6,"method":"components"}')" '"state":{"count":"6"}'
mark; rpc '{"jsonrpc":"2.0","id":7,"method":"type","params":{"text":"Y"}}' > /dev/null; sleep 0.3
check "control: type reaches the focused field" "$(since '^RW text' | tail -1)" 'RW text "Y"'
mark; rpc '{"jsonrpc":"2.0","id":8,"method":"press","params":{"target":"text:tap"}}' > /dev/null; sleep 0.3
check "control: press runs the reloaded handler" "$(since '^RW press' | tr '\n' ';')" "RW press count=8;"
shot s3
check "events: ready" "$(grep -c '"event":"ready"' "$EVENTS")" "1"
check "events: one reloaded per edit" "$(grep -c '"event":"reload","kind":"reloaded"' "$EVENTS")" "2"
has "events: the template edit rebuilt a region" "$(grep '"event":"refresh"' "$EVENTS" | head -1)" '"module":'

[ $FAILED = 0 ] && echo "RESULT PASS" || { echo "RESULT FAIL"; tail -30 "$LOG"; }
exit $FAILED
