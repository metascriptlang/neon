#!/usr/bin/env bash
# Frame delivery on Android: build bench/frames Release, install on $ANDROID_SERIAL (or the one device), launch it
# without touching it, and read the summary it shows once the measured 5 s are over.
# Usage: bench/frames/android/run.sh <label>   (from the Neon checkout; ION defaults to ../ion)
set -eu
cd "$(dirname "$0")/../../.."
label=$1
ION=${ION:-$PWD/../ion}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk} JAVA_HOME=${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}
r=/private/tmp/neon-bench-frames/$label-$(date +%H%M%S)
mkdir -p "$r/home"
step() { n=$1; shift; if ! "$@" > "$r/$n.log" 2>&1; then echo "FAIL $n: $r/$n.log"; tail -15 "$r/$n.log"; exit 1; fi; }
step install-ion env HOME="$r/home" msc install -g "@metascript/ion@file:$ION"
step generate env HOME="$r/home" "$r/home/.metascript/bin/ion" generate bench/frames/android/project.ms "$r/gradle"
step keystore keytool -genkeypair -keystore "$r/bench.jks" -storepass neonbench -keypass neonbench \
	-alias bench -keyalg RSA -keysize 2048 -validity 1 -dname CN=neon-bench
export ION_ANDROID_STORE_FILE="$r/bench.jks" ION_ANDROID_STORE_PASSWORD=neonbench ION_ANDROID_KEY_ALIAS=bench ION_ANDROID_KEY_PASSWORD=neonbench
step build sh -c "cd '$r/gradle' && ./gradlew assembleRelease --console=plain"
pkg=dev.neon.NeonFrames
adb uninstall "$pkg" > /dev/null 2>&1 || true
step install adb install "$r/gradle/app/build/outputs/apk/release/app-release.apk"
adb shell input keyevent KEYCODE_WAKEUP
adb shell am start -W -n "$pkg/dev.metascript.app.MainActivity" > "$r/start.log"
sleep 12
adb shell uiautomator dump /sdcard/frames.xml > /dev/null 2>&1
status=$(adb shell cat /sdcard/frames.xml | grep -o 'text="frames [^"]*"' | head -1)
adb shell am force-stop "$pkg"
case "$status" in *"frames done"*) echo "$label | $status";; *) echo "FAIL $label: not done after 12 s: $status"; exit 1;; esac
