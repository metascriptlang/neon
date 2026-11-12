#!/bin/sh
# Pulse's conformance suite on real Core Animation in the iOS simulator: generates
# examples/layerMotion/iosConformance with Ion, installs it on a throwaway iPhone 17 Pro
# simulator and reads the adapter's table from the app's console; the app exits with its
# failure count. Logs stay in the printed results directory.
set -eu
cd "$(dirname "$0")/../.."
neon=$PWD
ION=${ION:-$neon/../ion}
DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
results=$(mktemp -d /private/tmp/neon-ios-conformance.XXXXXX)
echo "== ios conformance results=$results"

step() {
	name=$1
	shift
	if ! "$@" > "$results/$name.log" 2>&1; then
		echo "FAIL: ios conformance $name; log $results/$name.log" >&2
		tail -20 "$results/$name.log" >&2
		exit 1
	fi
}

mkdir -p "$results/home"
step install-ion env HOME="$results/home" msc install -g "@metascript/ion@file:$ION"
ion() { HOME="$results/home" "$results/home/.metascript/bin/ion" "$@"; }

step generate ion generate examples/layerMotion/iosConformance/project.ms "$results/xcode"
step build xcodebuild -project "$results/xcode/NeonLayerConformance.xcodeproj" -target NeonLayerConformance \
	-configuration Debug -sdk iphonesimulator -jobs 1 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
	SYMROOT="$results/products" OBJROOT="$results/objects" \
	CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
app="$results/products/Debug-iphonesimulator/NeonLayerConformance.app"
bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Info.plist")

runtime=$(xcrun simctl list runtimes available | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)$/\1/p' | tail -1)
if [ -z "$runtime" ]; then
	echo "FAIL: ios conformance needs an installed iOS simulator runtime" >&2
	exit 1
fi
device=$(xcrun simctl create "Neon iOS conformance" "$DEVICE_TYPE" "$runtime")
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1; xcrun simctl delete "$device" >/dev/null 2>&1' EXIT INT TERM
step boot xcrun simctl bootstatus "$device" -b
step install xcrun simctl install "$device" "$app"

xcrun simctl launch --console-pty --terminate-running-process "$device" "$bundle" > "$results/console.log" 2>&1 || true
grep -E "conformance:|FAIL|mid-clip" "$results/console.log" || true
if ! grep -q "neon core animation conformance:" "$results/console.log"; then
	echo "FAIL: ios conformance printed no table; log $results/console.log" >&2
	exit 1
fi
if grep -q "^FAIL" "$results/console.log"; then
	echo "FAIL: ios conformance; log $results/console.log" >&2
	exit 1
fi
echo "PASS: ios conformance on real Core Animation"
