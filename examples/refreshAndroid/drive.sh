#!/bin/bash
# Drives Neon Refresh over MetaScript HCR on an Android device or emulator through the dev loop
# (tools/androidHcr.sh): template edits, a helper module edit, a compile error, an activity recreation,
# a setup edit and a core change, each checked on the running app. Pristine sources are copied into
# <repo>/out/refreshAndroid and the edits land there.
# usage: APK=<debug apk whose NativeApp loads files/hcr/libapp.core.so> examples/refreshAndroid/drive.sh
#   MSC, SERIAL, ABI, API, PACKAGE: see tools/androidHcr.sh
export MSYS_NO_PATHCONV=1
SRC=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SRC/../.." && pwd)
command -v cygpath > /dev/null && ROOT=$(cygpath -m "$ROOT")
WORK=$ROOT/out/refreshAndroid
LOG=$WORK/dev.log
SERIAL=${SERIAL:-emulator-5554}
PACKAGE=${PACKAGE:-dev.neon.NeonRefresh}
SDK=${ANDROID_HOME:-$(cygpath -m "$LOCALAPPDATA")/Android/Sdk}
ADB="$SDK/platform-tools/adb"
FAILED=0
SEEN=0
TIMES=""

adb() { "$ADB" -s "$SERIAL" "$@"; }
now() { date +%s%3N; }
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILED=1; }
check() { if [ "$2" = "$3" ]; then pass "$1: $2"; else fail "$1: got '$2', expected '$3'"; fi; }

texts() { adb shell "uiautomator dump /sdcard/neonRefresh.xml > /dev/null && cat /sdcard/neonRefresh.xml" | tr '>' '\n' | sed -n 's/.* text="\([^"]\+\)".* bounds="\([^"]*\)".*/\1|\2/p'; }
shown() { texts | cut -d'|' -f1 | tr '\n' ';'; }
tap() {
	local b; b=$(texts | grep "^$1|" | cut -d'|' -f2 | tr -c '0-9\n' ' ')
	set -- $b
	[ $# = 4 ] || return
	adb shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))
	sleep 0.5
}
showsWithin() {
	for i in $(seq 1 $2); do [ "$(shown)" = "$1" ] && return; sleep 0.3; done
}

# next <regex> <seconds>: the first dev-loop line after the last one consumed that matches, in LINE.
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
edit() { T0=$(now); sed -i "$2" "$WORK/$1"; }
# reloaded <name>: waits for the engine's answer to the last edit and prints where the time went.
reloaded() {
	next "^dev: device: HCR " 30 || { fail "$1: no answer from the engine"; return 1; }
	local answer=$LINE at=${LINE##* at } build deliver
	case "$answer" in *"HCR reloaded"*) ;; *) fail "$1: ${answer#dev: device: }"; return 1 ;; esac
	build=$(grep -E "^watch: build [0-9]+ (built|rebuilt)" "$LOG" | tail -1 | sed 's/.* in \([0-9]*\) ms.*/\1/')
	deliver=$(grep "^dev: delivered" "$LOG" | tail -1 | sed 's/.* in \([0-9]*\) ms.*/\1/')
	echo "timing $1: edit to reloaded $((at - T0)) ms = build $build + deliver $deliver + rest $((at - T0 - build - deliver))"
	TIMES="$TIMES $((at - T0))"
}

mkdir -p "$WORK"
for f in build.ms app.ms counter.ms words.ms; do cp "$SRC/$f" "$WORK/$f"; done
bash "$ROOT/tools/androidHcr.sh" "$WORK" > "$LOG" 2>&1 &
DEV=$!
trap 'kill $DEV 2> /dev/null; adb shell settings put system font_scale 1.0' EXIT
next "^dev: started" 180 || { tail -20 "$LOG"; fail "the dev loop did not start the app"; exit 1; }
UPDATED=$(adb shell dumpsys package $PACKAGE | grep lastUpdateTime)
showsWithin "Counter v1;count 0;press it;tap;" 30
check "start" "$(shown)" "Counter v1;count 0;press it;tap;"
[ $FAILED = 0 ] || { adb logcat -d -b crash | tail -5; exit 1; }
PID=$(adb shell pidof $PACKAGE)

# (f) the activity is recreated (font scale is not in the manifest's configChanges): the engine is
# not started twice, and the edits below show that one poll survives
adb shell settings put system font_scale 1.15
sleep 3
showsWithin "Counter v1;count 0;press it;tap;" 30
check "activity recreated before any reload: same process, mounted once" "$(shown) $(adb shell pidof $PACKAGE)" "Counter v1;count 0;press it;tap; $PID"

for i in 1 2 3; do tap tap; done
check "three taps" "$(shown)" "Counter v1;count 3;press it;tap;"

# (a) three template edits in a row: one view, one handler, the count kept
for v in 2 3 4; do
	edit counter.ms "s/>Counter v[0-9]*</>Counter v$v</"
	reloaded "template edit $v"
	showsWithin "Counter v$v;count $((v + 1));press it;tap;" 5
	check "template edit $v keeps the count and one view" "$(shown)" "Counter v$v;count $((v + 1));press it;tap;"
	tap tap
	check "template edit $v leaves one handler" "$(shown)" "Counter v$v;count $((v + 2));press it;tap;"
done

# (b) a helper module the component reads
edit words.ms 's/press it/press again/'
reloaded "helper edit"
showsWithin "Counter v4;count 6;press again;tap;" 5
check "helper edit shows without a tap, count kept" "$(shown)" "Counter v4;count 6;press again;tap;"

# (c) a compile error, then its fix
edit counter.ms 's/count() + 1/count( + 1/'
next "^watch: build [0-9]+ failed" 30 && pass "compile error ends the build: $LINE" || fail "compile error: no failed build"
grep -m1 "error" "$LOG" | sed 's/^/pc: /'
tap tap
check "the app still runs after a compile error" "$(shown)" "Counter v4;count 7;press again;tap;"
edit counter.ms 's/count( + 1/count() + 1/; s/>Counter v4</>Counter v5</'
reloaded "fix after the error"
showsWithin "Counter v5;count 7;press again;tap;" 5
check "the fix applies, count kept" "$(shown)" "Counter v5;count 7;press again;tap;"

# (d) a setup edit: the handler adds 2. The component remounts and its signals keep their values.
edit counter.ms 's/count() + 1/count() + 2/'
reloaded "setup edit"
check "setup edit keeps the count" "$(shown)" "Counter v5;count 7;press again;tap;"
tap tap
check "setup edit runs the new handler" "$(shown)" "Counter v5;count 9;press again;tap;"
THROW=' if (count() >= 0) { throw new Error("setup failed"); }'
edit counter.ms "s/createSignal(0);/createSignal(0);$THROW/"
reloaded "setup that throws"
showsWithin "counter.ms#Counter did not mount: setup failed;" 5
check "a setup that throws draws the error where the component was" "$(shown)" "counter.ms#Counter did not mount: setup failed;"
edit counter.ms "s/$THROW//"
reloaded "fix after the throw"
showsWithin "Counter v5;count 9;press again;tap;" 5
check "the fix mounts again with the count" "$(shown)" "Counter v5;count 9;press again;tap;"
check "same process through every edit" "$(adb shell pidof $PACKAGE)" "$PID"

# (e) a core change: the engine answers RestartRequired and the dev loop restarts the app
edit counter.ms 's/count() + 2/count() + 1/'
next "^dev: device: HCR " 30
echo "after restoring the setup: ${LINE#dev: device: }; $(shown)"
edit counter.ms 's/>Counter v5</>{"Counter v" + (splitmix32(6) == splitmix32(6) ? "6" : "?")}</; 1i import { splitmix32 } from "std/hash";'
next "^dev: device: HCR restart required" 60 && pass "core change: ${LINE#dev: device: }" || fail "core change: no restart required"
next "^dev: restarted" 30 && echo "$LINE (edit to restarted $(($(now) - T0)) ms)" || fail "core change: the dev loop did not restart the app"
showsWithin "Counter v6;count 0;press again;tap;" 30
check "restart runs the new core, state lost" "$(shown)" "Counter v6;count 0;press again;tap;"
NEWPID=$(adb shell pidof $PACKAGE)
[ -n "$NEWPID" ] && [ "$NEWPID" != "$PID" ] && pass "new process $NEWPID" || fail "restart: pid '$NEWPID' after '$PID'"
check "no reinstall" "$(adb shell dumpsys package $PACKAGE | grep lastUpdateTime)" "$UPDATED"
tap tap
check "tap after the restart" "$(shown)" "Counter v6;count 1;press again;tap;"
edit counter.ms 's/"6" : "?"/"7" : "?"/'
reloaded "template edit after the restart"
showsWithin "Counter v7;count 1;press again;tap;" 5
check "reload after the restart keeps the count" "$(shown)" "Counter v7;count 1;press again;tap;"

# (f) again, after a reload: the remount runs reloaded code against slots of the first generation
adb shell settings put system font_scale 1.0
sleep 3
showsWithin "Counter v7;count 0;press again;tap;" 10
check "activity recreation after a reload remounts in the same process" "$(shown) $(adb shell pidof $PACKAGE)" "Counter v7;count 0;press again;tap; $NEWPID"

echo "edit to reloaded, sorted ms:$(echo $TIMES | tr ' ' '\n' | sort -n | tr '\n' ' ')"
[ $FAILED = 0 ] && echo "RESULT PASS" || echo "RESULT FAIL"
exit $FAILED
