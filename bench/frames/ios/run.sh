#!/usr/bin/env bash
# Frame delivery on iOS: build bench/frames Release, launch it with its console attached, print the line it logs
# once the measured 5 s are over.
# Usage: [FRAMES_PROJECT=loadedProject] bench/frames/ios/run.sh <device-udid | sim> <label>   (from the Neon checkout; ION defaults to ../ion)
set -eu
cd "$(dirname "$0")/../../.."
target=$1
label=$2
ION=${ION:-$PWD/../ion}
r=/private/tmp/neon-bench-frames/$label-$(date +%H%M%S)
mkdir -p "$r/home"
step() { n=$1; shift; if ! "$@" > "$r/$n.log" 2>&1; then echo "FAIL $n: $r/$n.log"; tail -15 "$r/$n.log"; exit 1; fi; }
step install-ion env HOME="$r/home" msc install -g "@metascript/ion@file:$ION"
step generate env HOME="$r/home" "$r/home/.metascript/bin/ion" generate bench/frames/ios/${FRAMES_PROJECT:-project}.ms "$r/xcode"
if [ "$target" = sim ]; then
	runtime=$(xcrun simctl list runtimes available | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)$/\1/p' | tail -1)
	device=$(xcrun simctl create "Neon frames bench" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime")
	trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1; xcrun simctl delete "$device" >/dev/null 2>&1' EXIT INT TERM
	step build xcodebuild -project "$r/xcode/NeonFrames.xcodeproj" -target NeonFrames -configuration Release -sdk iphonesimulator -jobs 4 \
		ARCHS=arm64 ONLY_ACTIVE_ARCH=YES SYMROOT="$r/products" OBJROOT="$r/objects" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
	step boot xcrun simctl bootstatus "$device" -b
	step install xcrun simctl install "$device" "$r/products/Release-iphonesimulator/NeonFrames.app"
	timeout 30 xcrun simctl launch --console-pty "$device" dev.neon.NeonFrames > "$r/console.log" 2>&1 || true
else
	sign=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-4R7EAZY462}" "CODE_SIGN_IDENTITY=Apple Development")
	step build xcodebuild -project "$r/xcode/NeonFrames.xcodeproj" -target NeonFrames -configuration Release -sdk iphoneos -jobs 4 \
		ARCHS=arm64 ONLY_ACTIVE_ARCH=YES SYMROOT="$r/products" OBJROOT="$r/objects" -allowProvisioningUpdates "${sign[@]}" build
	xcrun devicectl device uninstall app --device "$target" dev.neon.NeonFrames > "$r/uninstall.log" 2>&1 || true
	step install xcrun devicectl device install app --device "$target" "$r/products/Release-iphoneos/NeonFrames.app"
	timeout 30 xcrun devicectl device process launch --console --terminate-existing --device "$target" dev.neon.NeonFrames > "$r/console.log" 2>&1 || true
fi
line=$(grep -a -m1 "frames done" "$r/console.log" || true)
[ -n "$line" ] || { echo "FAIL $label: no 'frames done' line in $r/console.log"; tail -5 "$r/console.log"; exit 1; }
echo "$label | $line"
