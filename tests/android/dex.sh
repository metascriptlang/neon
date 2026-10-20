#!/bin/sh
# Android Release dex: R8 keeps the Java class of a component or service domain only when the app
# imports it. Builds tests/android/minimal (View and Text) and tests/android/imports (Switch,
# Video, AsyncStorage) with Ion, reads the classes of each Release dex with dexdump and R8's
# mapping, and holds the minimal dex under its byte budget. Needs the Android SDK and NDK; installs nothing on a device.
# Usage: tests/android/dex.sh [results dir]; ION_HOME names a HOME holding an installed Ion.
set -u
cd "$(dirname "$0")/../.."
r=${1:-$(mktemp -d /private/tmp/neon-dex.XXXXXX)}
mkdir -p "$r"
echo "results=$r"
home=${ION_HOME:-$PWD/out/ion-home}
if [ ! -x "$home/.metascript/bin/ion" ]; then
	mkdir -p "$home"
	HOME="$home" msc install -g "@metascript/ion@file:${ION:-$PWD/../ion}" > "$r/install-ion.log" 2>&1 || { echo "FAIL install-ion"; tail -20 "$r/install-ion.log"; exit 1; }
fi
sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
dexdump=$(ls "$sdk"/build-tools/*/dexdump | sort -V | tail -1)
[ -x "$dexdump" ] || { echo "FAIL no dexdump under $sdk/build-tools"; exit 1; }
keytool -genkeypair -keystore "$r/dex.jks" -storepass neondex -keypass neondex \
	-alias dex -keyalg RSA -keysize 2048 -validity 1 -dname CN=neon-dex > "$r/keystore.log" 2>&1 || { echo "FAIL keystore"; exit 1; }
export ION_ANDROID_STORE_FILE="$r/dex.jks" ION_ANDROID_STORE_PASSWORD=neondex
export ION_ANDROID_KEY_ALIAS=dex ION_ANDROID_KEY_PASSWORD=neondex
fail=0

# expect_dex <app> "<classes the dex names>" "<classes no code comes from>" <dex byte budget or ->
expect_dex() {
	name=$(basename "$1")
	HOME="$home" "$home/.metascript/bin/ion" generate "$1/project.ms" "$r/$name" > "$r/$name.generate.log" 2>&1 || { echo "FAIL dex $name: generate"; fail=1; return; }
	(cd "$r/$name" && ./gradlew assembleRelease --console=plain) > "$r/$name.build.log" 2>&1 || { echo "FAIL dex $name: build, log $r/$name.build.log"; fail=1; return; }
	apk="$r/$name/app/build/outputs/apk/release/app-release.apk"
	map="$r/$name/app/build/outputs/mapping/release/mapping.txt"
	mkdir -p "$r/$name.dex"
	unzip -q -o "$apk" 'classes*.dex' -d "$r/$name.dex"
	dump="$r/$name.dex/dexdump.txt"
	: > "$dump"
	for f in "$r/$name.dex"/classes*.dex; do
		"$dexdump" "$f" >> "$dump" || { echo "FAIL dex $name: dexdump $f"; fail=1; return; }
	done
	classes=$(sed -n "s/^  Class descriptor  : 'L\(.*\);'/\1/p" "$dump")
	bytes=$(cat "$r/$name.dex"/classes*.dex | wc -c | tr -d ' ')
	bad=0
	for c in $2; do
		echo "$classes" | grep -qx "dev/metascript/neon/$c" || { echo "FAIL dex $name: misses $c"; bad=1; }
	done
	for c in $3; do
		grep -Eq "dev\.metascript\.neon\.$c([^A-Za-z0-9_]|$)" "$map" && { echo "FAIL dex $name: carries $c"; bad=1; }
	done
	awk '
		/Class descriptor/ { measurement = /Ldev\/metascript\/neon\/Measurement;/; method = 0; signature = 0 }
		/name[[:space:]]*:/ { method = measurement && /\047inWindow\047/; signature = 0 }
		/type[[:space:]]*:/ { signature = method && /\047\(Landroid\/view\/View;\)\[F\047/ }
		/access[[:space:]]*:/ && measurement && method && signature && /PUBLIC/ && /STATIC/ { found = 1 }
		END { exit !found }
	' "$dump" || { echo "FAIL dex $name: misses public static Measurement.inWindow(View):float[]"; bad=1; }
	awk '
		/^[^[:space:]#].* -> .*:$/ { measurement = /^dev\.metascript\.neon\.Measurement -> dev\.metascript\.neon\.Measurement:$/ }
		measurement && /float\[\] inWindow\(android\.view\.View\)(:[0-9]+)* -> inWindow$/ { found = 1 }
		END { exit !found }
	' "$map" || { echo "FAIL dex $name: renames Measurement JNI entry point"; bad=1; }
	if [ "$4" != - ] && [ "$bytes" -gt "$4" ]; then echo "FAIL dex $name: $bytes bytes, budget $4"; bad=1; fi
	[ $bad = 0 ] && echo "ok   dex $name $bytes bytes" || fail=1
}

components="Toggle Spinner Overlay Web Movie CameraPreview SvgView"
domains="NetInfo Geolocation Device Notifications NotificationReceiver"
expect_dex tests/android/minimal "App Props Picture Measurement" "$components Storage $domains" 135744
expect_dex tests/android/imports "Toggle Movie Storage Measurement" "Spinner Overlay Web CameraPreview SvgView $domains" -
exit $fail
