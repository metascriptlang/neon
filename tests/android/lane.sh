#!/bin/sh
# One Android lane on the device named by ANDROID_SERIAL: generate the example's Gradle project
# with Ion, build Debug, take the shared device lock, install, run the python driver.
# usage: ANDROID_SERIAL=<serial> tests/android/lane.sh <example dir> <package> <driver.py>
# ION_HOME names a HOME holding an installed Ion (default: a fresh install of ../ion under out/).
set -u
example=$1; package=$2; driver=$3
: "${ANDROID_SERIAL:?set ANDROID_SERIAL to the device}"
cd "$(dirname "$0")/../.."
r=$(mktemp -d /private/tmp/neon-lane.XXXXXX)
echo "results=$r serial=$ANDROID_SERIAL"
mkdir -p "$r/screenshots"
home=${ION_HOME:-$PWD/out/ion-home}
if [ ! -x "$home/.metascript/bin/ion" ]; then
	mkdir -p "$home"
	HOME="$home" msc install -g "@metascript/ion@file:${ION:-$PWD/../ion}" > "$r/install-ion.log" 2>&1 || { echo "FAIL install-ion"; tail -20 "$r/install-ion.log"; exit 1; }
fi
name=$(basename "$example")
HOME="$home" "$home/.metascript/bin/ion" generate "$example/android/project.ms" "$r/$name" > "$r/generate.log" 2>&1 || { echo "FAIL generate"; tail -20 "$r/generate.log"; exit 1; }
(cd "$r/$name" && ./gradlew assembleDebug --console=plain) > "$r/build.log" 2>&1 || { echo "FAIL build"; grep -E "rror" "$r/build.log" | head -30; exit 1; }
lock=/tmp/neon-device-$ANDROID_SERIAL.lock
until mkdir "$lock" 2>/dev/null; do sleep 20; done
trap 'rmdir "$lock"' EXIT
adb uninstall "$package" > /dev/null 2>&1 || true
adb install "$r/$name/app/build/outputs/apk/debug/app-debug.apk" > "$r/install.log" 2>&1 || { echo "FAIL install"; cat "$r/install.log"; exit 1; }
status=0
python3 "$driver" "$r" > "$r/driver.log" 2>&1 || status=$?
grep -E "NEON_ANDROID|FAIL|Traceback" "$r/driver.log" | cut -c1-300 | tail -8
echo "exit=$status"
exit $status
