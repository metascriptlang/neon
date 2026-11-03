#!/usr/bin/env bash
# Result latency on Android: build bench/wake Release, install on $ANDROID_SERIAL (or the one device), launch it
# without touching it, and read the latencies it prints once every job is done.
# Usage: bench/wake/android/run.sh <label>   (from the Neon checkout; ION defaults to ../ion)
set -eu
cd "$(dirname "$0")/../../.."
label=$1
ION=${ION:-$PWD/../ion}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk} JAVA_HOME=${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}
r=/private/tmp/neon-bench-wake/$label-$(date +%H%M%S)
mkdir -p "$r/home"
step() { n=$1; shift; if ! "$@" > "$r/$n.log" 2>&1; then echo "FAIL $n: $r/$n.log"; tail -15 "$r/$n.log"; exit 1; fi; }
step install-ion env HOME="$r/home" msc install -g "@metascript/ion@file:$ION"
step generate env HOME="$r/home" "$r/home/.metascript/bin/ion" generate bench/wake/android/project.ms "$r/gradle"
step keystore keytool -genkeypair -keystore "$r/bench.jks" -storepass neonbench -keypass neonbench \
	-alias bench -keyalg RSA -keysize 2048 -validity 1 -dname CN=neon-bench
export ION_ANDROID_STORE_FILE="$r/bench.jks" ION_ANDROID_STORE_PASSWORD=neonbench ION_ANDROID_KEY_ALIAS=bench ION_ANDROID_KEY_PASSWORD=neonbench
step build sh -c "cd '$r/gradle' && ./gradlew assembleRelease --console=plain"
pkg=dev.neon.NeonWake
adb uninstall "$pkg" > /dev/null 2>&1 || true
step install adb install "$r/gradle/app/build/outputs/apk/release/app-release.apk"
adb shell input keyevent KEYCODE_WAKEUP
adb shell am start -W -n "$pkg/dev.metascript.app.MainActivity" > "$r/start.log"
sleep 45
adb shell uiautomator dump /sdcard/wake.xml > /dev/null 2>&1
status=$(adb shell cat /sdcard/wake.xml | grep -o 'text="wake [^"]*"' | head -1)
adb shell am force-stop "$pkg"
case "$status" in *"wake done"*) echo "$label | $status";; *) echo "FAIL $label: not done after 45 s: $status"; exit 1;; esac
