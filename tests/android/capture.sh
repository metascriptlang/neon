#!/bin/sh
# Neon capture Android lane: generates examples/capture with Ion, adds the permissions
# its demo requests to the generated app manifest (Ion's description has no permission list),
# builds Debug, and, unless --build-only, installs it on ANDROID_SERIAL and drives it with
# tests/android/capture.py (exit 2 when the device is asleep or locked).
# Usage: tests/android/capture.sh [--build-only] [results dir]
set -eu
cd "$(dirname "$0")/../.."
build_only=0
if [ "${1:-}" = "--build-only" ]; then build_only=1; shift; fi
r=${1:-$(mktemp -d /private/tmp/neon-capture.XXXXXX)}
mkdir -p "$r"
echo "results=$r"
ionhome=${ION_HOME:-/private/tmp/ion-flatlist-prerequisite.jU95av/home}
HOME=$ionhome "$ionhome/.metascript/bin/ion" generate examples/capture/android/project.ms "$r/gradle" > "$r/generate.log" 2>&1 || { echo FAIL generate; tail -20 "$r/generate.log"; exit 1; }
manifest="$r/gradle/app/src/main/AndroidManifest.xml"
for permission in CAMERA RECORD_AUDIO; do
	sed -i '' "s|<application|<uses-permission android:name=\"android.permission.$permission\" />\\
	<application|" "$manifest"
done
grep -c uses-permission "$manifest" > /dev/null || { echo "FAIL manifest patch"; exit 1; }
(cd "$r/gradle" && ./gradlew assembleDebug --console=plain) > "$r/build.log" 2>&1 || { echo FAIL build; grep -E "error|FAILED" "$r/build.log" | head -30; exit 1; }
apk="$r/gradle/app/build/outputs/apk/debug/app-debug.apk"
echo "apk=$apk"
if [ "$build_only" = 1 ]; then exit 0; fi
adb uninstall dev.neon.NeonCapture > /dev/null 2>&1 || true
adb install "$apk" > "$r/install.log" 2>&1 || { echo FAIL install; cat "$r/install.log"; exit 1; }
python3 tests/android/capture.py "$r"
