#!/bin/bash
# Drives Neon Refresh over MetaScript HCR on an Android device or emulator: installs the APK once,
# delivers the images, taps the counter to 3, edits the template text and checks the running app.
# Pristine sources are copied into <repo>/out/refreshAndroid and the edit lands there.
# usage: APK=<debug apk whose NativeApp loads files/hcr/libapp.core.so> examples/refreshAndroid/drive.sh
#   MSC      compiler with the Android HCR link adapter (default: msc)
#   SERIAL   adb device (default: emulator-5554)
#   ABI      x86_64 | aarch64 (default: x86_64)
#   PACKAGE  application id of the APK (default: dev.neon.NeonRefresh)
export MSYS_NO_PATHCONV=1
SRC=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SRC/../.." && pwd)
command -v cygpath > /dev/null && ROOT=$(cygpath -m "$ROOT")
WORK=$ROOT/out/refreshAndroid
MSC=${MSC:-msc}
SERIAL=${SERIAL:-emulator-5554}
ABI=${ABI:-x86_64}
PACKAGE=${PACKAGE:-dev.neon.NeonRefresh}
SDK=${ANDROID_HOME:-$(cygpath -m "$LOCALAPPDATA")/Android/Sdk}
NDK=${ANDROID_NDK_HOME:-$(ls -d "$SDK"/ndk/* | tail -1)}
CC=$(ls "$NDK"/toolchains/llvm/prebuilt/*/bin/clang.exe 2>/dev/null || ls "$NDK"/toolchains/llvm/prebuilt/*/bin/clang)
ADB="$SDK/platform-tools/adb"
STAGE=/data/local/tmp/neonRefresh
FAILED=0

adb() { "$ADB" -s "$SERIAL" "$@"; }
now() { date +%s%3N; }
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILED=1; }
check() { if [ "$2" = "$3" ]; then pass "$1: $2"; else fail "$1: got '$2', expected '$3'"; fi; }

build() {
	(cd "$WORK" && "$MSC" build --hcr app.ms --os=android --cpu=$ABI --app=lib "--cc=$CC" \
		--passC=--target=$ABI-linux-android34 --passL=--target=$ABI-linux-android34 --passL=--driver-mode=g++ \
		--output=img/libapp.so --no-color) > "$WORK/build.log" 2>&1 || { tail -5 "$WORK/build.log"; fail "build"; exit 1; }
}

# deliver: every image that differs from the one last sent, then the .hcrabi that triggers the reload.
# A file is copied beside its target and renamed, so a loaded image is never rewritten in place.
deliver() {
	local names=""
	for f in "$WORK"/img/*.so; do
		cmp -s "$f" "$WORK/sent/$(basename "$f")" || names="$names $(basename "$f")"
	done
	names="$names libapp.so.hcrabi"
	for n in $names; do adb push "$WORK/img/$n" "$STAGE/$n" > /dev/null 2>&1 || fail "push $n"; done
	adb shell "run-as $PACKAGE sh -c 'mkdir -p files/hcr && cd files/hcr && for n in $names; do cp $STAGE/\$n \$n.new && chmod 444 \$n.new && mv -f \$n.new \$n || exit 1; done; date +%s%3N > delivered.at'" || fail "deliver"
	for n in $names; do cp "$WORK/img/$n" "$WORK/sent/$n"; done
	echo "delivered:$names"
}

texts() { adb shell "uiautomator dump /sdcard/neonRefresh.xml > /dev/null && cat /sdcard/neonRefresh.xml" | tr '>' '\n' | sed -n 's/.* text="\([^"]\+\)".* bounds="\([^"]*\)".*/\1|\2/p'; }
shown() { texts | cut -d'|' -f1 | tr '\n' ';'; }
tap() {
	local b; b=$(texts | grep "^$1|" | cut -d'|' -f2 | tr -c '0-9\n' ' ')
	set -- $b
	adb shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))
}
reloads() { adb logcat -d -v epoch -s Neon:I | grep -c "HCR "; }

mkdir -p "$WORK/sent"
rm -f "$WORK"/sent/*
for f in build.ms app.ms counter.ms; do cp "$SRC/$f" "$WORK/$f"; done
build
adb shell am force-stop $PACKAGE
adb install -r "$APK" > /dev/null || { fail "install $APK"; exit 1; }
adb shell "rm -rf $STAGE; mkdir -p $STAGE; run-as $PACKAGE rm -rf files/hcr"
deliver
adb logcat -c
adb shell am start -n $PACKAGE/dev.metascript.app.MainActivity > /dev/null
for i in $(seq 1 20); do [ "$(shown)" = "Counter v1;count 0;tap;" ] && break; sleep 0.5; done
check "start" "$(shown)" "Counter v1;count 0;tap;"
[ $FAILED = 0 ] || { adb shell "run-as $PACKAGE cat files/hcr/stderr.log"; exit 1; }
PID=$(adb shell pidof $PACKAGE)
echo "pid $PID"
for i in 1 2 3; do tap tap; done
sleep 0.5
check "three taps" "$(shown)" "Counter v1;count 3;tap;"

T0=$(now)
cp "$SRC/edits/counter.v2.ms" "$WORK/counter.ms"
build
T1=$(now)
deliver
T2=$(now)
for i in $(seq 1 20); do [ "$(reloads)" -gt 0 ] && break; sleep 0.5; done
adb logcat -d -v epoch -s Neon:I | grep "HCR "
AT=$(adb shell "run-as $PACKAGE cat files/hcr/delivered.at" | tr -d '\r')
SEEN=$(adb logcat -d -v epoch -s Neon:I | grep -m1 "HCR " | sed 's/^ *\([0-9]*\)\.\([0-9]*\).*/\1\2/')
echo "timing: rebuild $((T1 - T0)) ms, push $((T2 - T1)) ms, delivered to reloaded on the device $((SEEN - AT)) ms, edit to reloaded $((T2 - T0 + SEEN - AT)) ms"
check "template edit keeps the count" "$(shown)" "Counter v2;count 3;tap;"
check "same process" "$(adb shell pidof $PACKAGE)" "$PID"
tap tap
sleep 0.5
check "tap after the reload" "$(shown)" "Counter v2;count 4;tap;"
check "one reload, no other engine answer" "$(reloads)" "1"
adb shell "run-as $PACKAGE cat files/hcr/stderr.log" | grep "^HCR" | sed 's/^/stderr: /'
[ $FAILED = 0 ] && echo "RESULT PASS" || echo "RESULT FAIL"
exit $FAILED
