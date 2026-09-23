#!/bin/sh
# Neon Android emulator lane — generates the counter's Gradle project with Ion,
# builds Debug and Release, installs Debug on the emulator named by
# ANDROID_SERIAL and drives it with tests/android/counter.py. Logs and
# screenshots stay in the printed results directory.
set -eu
cd "$(dirname "$0")/../.."
neon=$PWD
ION=${ION:-$neon/../ion}
case "${ANDROID_SERIAL:-}" in
emulator-*) ;;
*)
	echo "FAIL: android lane needs ANDROID_SERIAL=emulator-<port>; it never drives a physical device" >&2
	exit 1
	;;
esac
results=$(mktemp -d /private/tmp/neon-android.XXXXXX)
echo "== android results=$results serial=$ANDROID_SERIAL"

step() {
	name=$1
	shift
	if ! "$@" > "$results/$name.log" 2>&1; then
		echo "FAIL: android $name; log $results/$name.log" >&2
		tail -20 "$results/$name.log" >&2
		exit 1
	fi
}

step generate "$ION/tooling/generator/ion-generate" examples/android/project.ms "$results/gradle"
step keystore keytool -genkeypair -keystore "$results/lane.jks" -storepass neonlane -keypass neonlane \
	-alias lane -keyalg RSA -keysize 2048 -validity 1 -dname CN=neon-lane
export ION_ANDROID_STORE_FILE="$results/lane.jks" ION_ANDROID_STORE_PASSWORD=neonlane
export ION_ANDROID_KEY_ALIAS=lane ION_ANDROID_KEY_PASSWORD=neonlane
step build sh -c "cd '$results/gradle' && ./gradlew assembleDebug assembleRelease --console=plain"
step boot sh -c 'until [ "$(adb shell getprop sys.boot_completed | tr -d "\r")" = 1 ]; do sleep 2; done'
adb uninstall dev.neon.NeonCounter > /dev/null 2>&1 || true
step install adb install "$results/gradle/app/build/outputs/apk/debug/app-debug.apk"

status=0
python3 tests/android/counter.py "$results" > "$results/lane.log" 2>&1 || status=$?
grep -E "NEON_ANDROID|FAIL" "$results/lane.log" || true
if [ "$status" -ne 0 ]; then
	echo "FAIL: android lane exit $status; log $results/lane.log" >&2
	exit "$status"
fi
echo "PASS: android counter rotation, lifecycle and press; screenshots $results/screenshots"
