#!/bin/bash
# Hot reload loop for a Neon app on an Android device or emulator, until interrupted: builds the HCR
# images in a warm watch session, installs the APK when the device holds another one, delivers the
# images, starts the app, then sends the images each rebuild changed. When the engine answers
# RestartRequired the app is restarted on the images already delivered (state lost, no reinstall).
# usage: APK=<debug apk whose NativeApp loads files/hcr/libapp.core.so> tools/androidHcr.sh <project dir> [entry.ms]
#   MSC       compiler with the Android HCR link adapter (default: msc)
#   SERIAL    adb device (default: emulator-5554)
#   ABI       x86_64 | aarch64 (default: x86_64)
#   API       Android API level of the images (default: 26)
#   PACKAGE   application id of the APK (default: dev.neon.NeonRefresh)
#   ACTIVITY  activity to start (default: dev.metascript.app.MainActivity)
#   NEON_CONTROL  a TCP port: the app serves the devtools control channel there and adb forwards
#                 the same port on this machine to it (docs/DEVTOOLS.md)
export MSYS_NO_PATHCONV=1
DIR=$(cd "${1:?usage: tools/androidHcr.sh <project dir> [entry.ms]}" && pwd)
command -v cygpath > /dev/null && DIR=$(cygpath -m "$DIR")
ENTRY=${2:-app.ms}
MSC=${MSC:-msc}
SERIAL=${SERIAL:-emulator-5554}
ABI=${ABI:-x86_64}
API=${API:-26}
PACKAGE=${PACKAGE:-dev.neon.NeonRefresh}
ACTIVITY=${ACTIVITY:-dev.metascript.app.MainActivity}
SDK=${ANDROID_HOME:-$(cygpath -m "$LOCALAPPDATA")/Android/Sdk}
NDK=${ANDROID_NDK_HOME:-$(ls -d "$SDK"/ndk/* | tail -1)}
CC=$(ls "$NDK"/toolchains/llvm/prebuilt/*/bin/clang.exe 2>/dev/null || ls "$NDK"/toolchains/llvm/prebuilt/*/bin/clang)
ADB="$SDK/platform-tools/adb"
IMG=$DIR/img
EVENTS=$DIR/img/events.fifo
STAGE=/data/local/tmp/$PACKAGE.hcr
TRIPLE=$ABI-linux-android$API
STARTED=0

adb() { "$ADB" -s "$SERIAL" "$@"; }
now() { NOW=${EPOCHREALTIME/[.,]/}; NOW=${NOW:0:13}; }
say() { echo "dev: $1"; }

# Sends the images written since the last delivery. A file is copied beside its target and renamed,
# so a loaded image is never rewritten in place; the .hcrabi goes last because the engine reads it
# as "this build is complete".
deliver() {
	local names="" paths="" t0 f n
	now; t0=$NOW
	: > "$IMG/sending"
	for f in "$IMG"/*.so "$IMG/libapp.so.hcrabi"; do
		n=${f##*/}
		[ $n != libapp.so.hcrabi ] && ! [ "$f" -nt "$IMG/sent" ] && continue
		names="$names $n"
		paths="$paths $f"
	done
	adb push $paths $STAGE/ > /dev/null 2>&1 || { say "delivery failed: adb push"; return 1; }
	adb shell "run-as $PACKAGE sh -c 'mkdir -p files/hcr && cd files/hcr && for n in $names; do cp $STAGE/\$n \$n.new && chmod 444 \$n.new && mv -f \$n.new \$n || exit 1; done'" || { say "delivery failed: copy into the app"; return 1; }
	mv -f "$IMG/sending" "$IMG/sent"
	now; say "delivered$names in $((NOW - t0)) ms"
}

installIfNeeded() {
	local sum; sum=$(md5sum "$APK" | cut -d' ' -f1)
	if [ -n "$(adb shell pm path $PACKAGE)" ] && [ "$(adb shell cat /data/local/tmp/$PACKAGE.apk.md5 2>/dev/null | tr -d '\r')" = "$sum" ]; then
		say "apk already installed"
		return
	fi
	adb install -r "$APK" > /dev/null || { say "cannot install $APK"; exit 1; }
	adb shell "echo $sum > /data/local/tmp/$PACKAGE.apk.md5"
	say "installed $APK"
}

startApp() {
	adb shell am force-stop $PACKAGE
	adb shell am start -n $PACKAGE/$ACTIVITY > /dev/null
	say "started $PACKAGE pid $(for i in 1 2 3 4 5 6 7 8 9 10; do p=$(adb shell pidof $PACKAGE | tr -d '\r'); [ -n "$p" ] && break; sleep 0.2; done; echo $p)"
}

built() {
	if [ $STARTED = 1 ]; then deliver; return; fi
	installIfNeeded
	adb shell am force-stop $PACKAGE
	adb shell "rm -rf $STAGE; mkdir -p $STAGE; run-as $PACKAGE rm -rf files/hcr"
	rm -f "$IMG/sent"
	deliver || exit 1
	devtools
	startApp
	STARTED=1
}

devtools() {
	[ -n "$NEON_CONTROL" ] || return 0
	adb shell "run-as $PACKAGE sh -c 'echo NEON_CONTROL=$NEON_CONTROL > files/hcr/devtools.env'" || { say "cannot write devtools.env"; exit 1; }
	adb forward tcp:$NEON_CONTROL tcp:$NEON_CONTROL > /dev/null || { say "adb forward tcp:$NEON_CONTROL failed"; exit 1; }
	say "devtools control channel on 127.0.0.1:$NEON_CONTROL"
}

[ -f "$APK" ] || { echo "APK=<debug apk> is required"; exit 1; }
mkdir -p "$IMG"
rm -f "$EVENTS"
mkfifo "$EVENTS"
exec 3<> "$EVENTS"
adb logcat -c
(cd "$DIR" && exec "$MSC" build --hcr --watch "$ENTRY" --os=android --cpu=$ABI --app=lib "--cc=$CC" \
	--passC=--target=$TRIPLE --passL=--target=$TRIPLE --passL=--driver-mode=g++ --output=img/libapp.so --no-color) > "$EVENTS" 2>&1 &
WATCH=$!
"$ADB" -s "$SERIAL" logcat -v tag -s MetaScript:I > "$EVENTS" 2>&1 &
LOGCAT=$!
trap 'kill $WATCH $LOGCAT 2> /dev/null; rm -f "$EVENTS"' EXIT
trap 'exit 0' INT TERM

while IFS= read -r line <&3; do
	line=${line%$'\r'}
	case "$line" in
	"watch: build "*" failed in"*)
		echo "$line"
		say "the build failed, the app keeps running the last delivered build" ;;
	"watch: build "*" up-to-date in"*)
		echo "$line" ;;
	"watch: build "*)
		echo "$line"
		built ;;
	"I/MetaScript"*": HCR restart required"*)
		say "device: ${line#*: }"
		startApp
		say "restarted on the delivered images" ;;
	"I/MetaScript"*": HCR "*)
		now; say "device: ${line#*: } at $NOW" ;;
	"I/MetaScript"* | "E/MetaScript"*)
		say "device: ${line#*: }" ;;
	"-----"*) ;;
	*)
		echo "$line" ;;
	esac
done
