#!/bin/sh
# A <Void> in the Neon iOS native host, beside a native View, on a throwaway iPhone simulator:
# tests/ios/voidAreaUITests.swift counts the area's colour and its 40pt marker in screenshots
# before and after rotation, and taps the area until onPointerDown inside it reports the tap.
set -eu
cd "$(dirname "$0")/../.."
neon=$PWD
ION=${ION:-$neon/../ion}
DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
results=$(mktemp -d /private/tmp/neon-void-area.XXXXXX)
echo "== void-area results=$results"

step() {
	name=$1
	shift
	if ! "$@" > "$results/$name.log" 2>&1; then
		echo "FAIL: void-area $name; log $results/$name.log" >&2
		tail -20 "$results/$name.log" >&2
		exit 1
	fi
}

mkdir -p "$results/home"
step install-ion env HOME="$results/home" msc install -g "@metascript/ion@file:$ION"
ion() { HOME="$results/home" "$results/home/.metascript/bin/ion" "$@"; }
step generate ion generate tests/ios/voidArea/project.ms "$results/xcode"
step build xcodebuild -project "$results/xcode/NeonVoidArea.xcodeproj" -target NeonVoidArea \
	-configuration Debug -sdk iphonesimulator -jobs 1 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
	SYMROOT="$results/products" OBJROOT="$results/objects" \
	CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

runtime=$(xcrun simctl list runtimes available | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)$/\1/p' | tail -1)
if [ -z "$runtime" ]; then
	echo "FAIL: void-area needs an installed iOS simulator runtime" >&2
	exit 1
fi
device=$(xcrun simctl create "Neon void-area" "$DEVICE_TYPE" "$runtime")
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1; xcrun simctl delete "$device" >/dev/null 2>&1' EXIT INT TERM
step boot xcrun simctl bootstatus "$device" -b
step install xcrun simctl install "$device" "$results/products/Debug-iphonesimulator/NeonVoidArea.app"

status=0
xcodebuild test -project tests/ios/counter.xcodeproj -scheme CounterUITests \
	-only-testing:CounterUITests/VoidAreaUITests -destination "id=$device" \
	-derivedDataPath "$results/derived" -resultBundlePath "$results/result.xcresult" \
	> "$results/test.log" 2>&1 || status=$?
xcrun xcresulttool export attachments --path "$results/result.xcresult" \
	--output-path "$results/screenshots" > "$results/attachments.log" 2>&1 || true
grep -E "NEON_VOID_AREA|error:|Test Case .*(passed|failed)" "$results/test.log" || true
if [ "$status" -ne 0 ]; then
	echo "FAIL: void-area test exit $status; log $results/test.log; screenshots $results/screenshots" >&2
	exit "$status"
fi
echo "PASS: void-area draws, follows rotation and takes a tap; screenshots $results/screenshots"
