#!/bin/sh
# Neon device-modules iOS lane: builds examples/device with the usage descriptions its
# permission requests need (Ion's generated Info.plist has no entry for them), installs it
# on a throwaway simulator whose location is set, and runs DeviceUITests from
# tests/ios/counterUITests.swift. Serialized with the other simulator lanes by
# /tmp/neon-sim.lock. Usage: tests/ios/device.sh [results dir]
set -u
cd "$(dirname "$0")/../.."
r=${1:-$(mktemp -d /private/tmp/neon-device.XXXXXX)}
mkdir -p "$r"
echo "results=$r"
ionhome=${ION_HOME:-/private/tmp/ion-flatlist-prerequisite.jU95av/home}
HOME=$ionhome "$ionhome/.metascript/bin/ion" generate examples/device/ios/project.ms "$r/xcode" > "$r/generate.log" 2>&1 || { echo FAIL generate; tail -20 "$r/generate.log"; exit 1; }
xcodebuild -project "$r/xcode/NeonDevice.xcodeproj" -target NeonDevice -configuration Debug -sdk iphonesimulator -jobs 2 \
	ARCHS=arm64 ONLY_ACTIVE_ARCH=YES SYMROOT="$r/products" OBJROOT="$r/objects" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
	"INFOPLIST_KEY_NSLocationWhenInUseUsageDescription=Neon reads your position for the device demo." \
	"INFOPLIST_KEY_NSCameraUsageDescription=Neon checks camera permission in the device demo." \
	"INFOPLIST_KEY_NSMicrophoneUsageDescription=Neon checks microphone permission in the device demo." \
	build > "$r/build.log" 2>&1 || { echo FAIL build; grep -E "error" "$r/build.log" | head -30; exit 1; }
until mkdir /tmp/neon-sim.lock 2>/dev/null; do sleep 15; done
release_sim() { rmdir /tmp/neon-sim.lock 2>/dev/null; }
runtime=$(xcrun simctl list runtimes available | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)$/\1/p' | tail -1)
device=$(xcrun simctl create "Neon rn-device" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime")
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1; xcrun simctl delete "$device" >/dev/null 2>&1; release_sim' EXIT
xcrun simctl bootstatus "$device" -b > "$r/boot.log" 2>&1
xcrun simctl location "$device" set 10.7769,106.7009 >> "$r/boot.log" 2>&1
xcrun simctl install "$device" "$r/products/Debug-iphonesimulator/NeonDevice.app" || { echo FAIL install; exit 1; }
status=0
xcodebuild test -project tests/ios/counter.xcodeproj -scheme CounterUITests -only-testing:CounterUITests/DeviceUITests \
	-destination "id=$device" -derivedDataPath "$r/derived" -resultBundlePath "$r/result.xcresult" > "$r/test.log" 2>&1 || status=$?
mkdir -p "$r/shots"
xcrun xcresulttool export attachments --path "$r/result.xcresult" --output-path "$r/shots" > /dev/null 2>&1 || true
grep -E "NEON_IOS|error:|Test Case .*(passed|failed)|XCTAssert|Executed" "$r/test.log" | cut -c1-400 | head -40
echo "exit=$status"
exit $status
