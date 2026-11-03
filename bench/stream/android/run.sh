#!/usr/bin/env bash
# S1 on Android: build bench/stream Release, install on $ANDROID_SERIAL (or the one device), fling it while it streams,
# and read each iteration's frames from dumpsys gfxinfo.
# Usage: bench/stream/android/run.sh <label> [iterations]   (from the Neon checkout; ION defaults to ../ion)
set -eu
cd "$(dirname "$0")/../../.."
label=$1
iterations=${2:-5}
ION=${ION:-$PWD/../ion}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk} JAVA_HOME=${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}
r=/private/tmp/neon-bench-stream/$label-$(date +%H%M%S)
mkdir -p "$r/home"
step() { n=$1; shift; if ! "$@" > "$r/$n.log" 2>&1; then echo "FAIL $n: $r/$n.log"; tail -15 "$r/$n.log"; exit 1; fi; }
step install-ion env HOME="$r/home" msc install -g "@metascript/ion@file:$ION"
step generate env HOME="$r/home" "$r/home/.metascript/bin/ion" generate bench/stream/android/project.ms "$r/gradle"
step keystore keytool -genkeypair -keystore "$r/bench.jks" -storepass neonbench -keypass neonbench \
	-alias bench -keyalg RSA -keysize 2048 -validity 1 -dname CN=neon-bench
export ION_ANDROID_STORE_FILE="$r/bench.jks" ION_ANDROID_STORE_PASSWORD=neonbench ION_ANDROID_KEY_ALIAS=bench ION_ANDROID_KEY_PASSWORD=neonbench
step build sh -c "cd '$r/gradle' && ./gradlew assembleRelease --console=plain"
pkg=dev.neon.NeonStream
adb uninstall "$pkg" > /dev/null 2>&1 || true
step install adb install "$r/gradle/app/build/outputs/apk/release/app-release.apk"
size=$(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)
w=${size% *}; h=${size#* }
x=$((w / 2)); low=$((h * 4 / 5)); high=$((h / 5))
adb shell input keyevent KEYCODE_WAKEUP
adb shell am start -W -n "$pkg/dev.metascript.app.MainActivity" > "$r/start.log"
sleep 3
for i in $(seq 1 "$iterations"); do
	adb shell dumpsys gfxinfo "$pkg" reset > /dev/null
	adb shell input swipe "$x" "$low" "$x" "$high" 60
	adb shell input swipe "$x" "$low" "$x" "$high" 60
	adb shell input swipe "$x" "$high" "$x" "$low" 60
	sleep 2
	adb shell dumpsys gfxinfo "$pkg" > "$r/gfxinfo-$i.txt"
done
adb shell am force-stop "$pkg"
python3 - "$r" "$label" "$iterations" <<'PY'
import re, sys, statistics
r, label, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
keys = [("Total frames rendered", r"Total frames rendered: (\d+)"), ("Janky frames", r"Janky frames: (\d+)"),
        ("p50 ms", r"50th percentile: (\d+)ms"), ("p90 ms", r"90th percentile: (\d+)ms"),
        ("p99 ms", r"99th percentile: (\d+)ms"), ("Missed vsync", r"Number Missed Vsync: (\d+)"),
        ("Slow UI thread", r"Number Slow UI thread: (\d+)")]
rows = {k: [] for k, _ in keys}
for i in range(1, n + 1):
    text = open(f"{r}/gfxinfo-{i}.txt").read()
    for k, pat in keys:
        m = re.search(pat, text)
        if not m: sys.exit(f"FAIL gfxinfo-{i}.txt has no '{k}'")
        rows[k].append(int(m.group(1)))
for k, _ in keys:
    v = rows[k]
    print(f"{label} | {k} | median {statistics.median(v)} | runs {', '.join(map(str, v))}")
print(f"results: {r}")
PY
