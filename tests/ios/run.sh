#!/bin/sh
# Neon iOS simulator lane — generates the counter, the scroll list and the
# 10000-row FlatList Xcode projects with Ion, builds and installs them on a
# throwaway iPhone 17 Pro simulator, then drives them with
# tests/ios/counterUITests.swift, sampling the FlatList app's RSS meanwhile.
# Logs and screenshots stay in the printed results directory.
set -eu
cd "$(dirname "$0")/../.."
neon=$PWD
ION=${ION:-$neon/../ion}
DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
results=$(mktemp -d /private/tmp/neon-ios.XXXXXX)
echo "== ios results=$results"

step() {
	name=$1
	shift
	if ! "$@" > "$results/$name.log" 2>&1; then
		echo "FAIL: ios $name; log $results/$name.log" >&2
		tail -20 "$results/$name.log" >&2
		exit 1
	fi
}

mkdir -p "$results/home"
step install-ion env HOME="$results/home" msc install -g "@metascript/ion@file:$ION"
ion() { HOME="$results/home" "$results/home/.metascript/bin/ion" "$@"; }

step generate ion generate examples/ios/project.ms "$results/xcode"
step build xcodebuild -project "$results/xcode/NeonCounter.xcodeproj" -target NeonCounter \
	-configuration Debug -sdk iphonesimulator -jobs 1 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
	SYMROOT="$results/products" OBJROOT="$results/objects" \
	CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
step generate-list ion generate examples/list/ios/project.ms "$results/xcode-list"
step generate-flatlist ion generate examples/flatlist/ios/project.ms "$results/xcode-flatlist"
step build-list xcodebuild -project "$results/xcode-list/NeonList.xcodeproj" -target NeonList \
	-configuration Debug -sdk iphonesimulator -jobs 1 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
	SYMROOT="$results/products" OBJROOT="$results/objects-list" \
	CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
step build-flatlist xcodebuild -project "$results/xcode-flatlist/NeonFlatList.xcodeproj" -target NeonFlatList \
	-configuration Debug -sdk iphonesimulator -jobs 1 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
	SYMROOT="$results/products" OBJROOT="$results/objects-flatlist" \
	CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

runtime=$(xcrun simctl list runtimes available | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)$/\1/p' | tail -1)
if [ -z "$runtime" ]; then
	echo "FAIL: ios lane needs an installed iOS simulator runtime" >&2
	exit 1
fi
device=$(xcrun simctl create "Neon iOS lane" "$DEVICE_TYPE" "$runtime")
trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1; xcrun simctl delete "$device" >/dev/null 2>&1' EXIT INT TERM
step boot xcrun simctl bootstatus "$device" -b
step install xcrun simctl install "$device" "$results/products/Debug-iphonesimulator/NeonCounter.app"
step install-list xcrun simctl install "$device" "$results/products/Debug-iphonesimulator/NeonList.app"
step install-flatlist xcrun simctl install "$device" "$results/products/Debug-iphonesimulator/NeonFlatList.app"

(while kill -0 $$ 2>/dev/null; do
	app=$(pgrep -x NeonFlatList | head -1)
	if [ -n "$app" ]; then ps -o rss= -p "$app" >> "$results/flatlist-rss.log" 2>/dev/null; fi
	sleep 1
done) &
sampler=$!
status=0
xcodebuild test -project tests/ios/counter.xcodeproj -scheme CounterUITests \
	-destination "id=$device" -derivedDataPath "$results/derived" \
	-resultBundlePath "$results/result.xcresult" > "$results/test.log" 2>&1 || status=$?
xcrun xcresulttool export attachments --path "$results/result.xcresult" \
	--output-path "$results/screenshots" > "$results/attachments.log" 2>&1 || true
python3 - "$results/screenshots" <<'EOF' || true
import json, os, sys
root = sys.argv[1]
for test in json.load(open(os.path.join(root, "manifest.json"))):
    for a in test["attachments"]:
        name = a["suggestedHumanReadableName"].split("_0_")[0].replace("/", "-")
        ext = os.path.splitext(a["exportedFileName"])[1]
        if not name.endswith(ext): name += ext
        os.rename(os.path.join(root, a["exportedFileName"]), os.path.join(root, name))
EOF
kill "$sampler" 2>/dev/null || true
grep -E "NEON_IOS|error:|Test Case .*(passed|failed)" "$results/test.log" || true
echo "NEON_IOS flatlist-rss max_kb=$(sort -n "$results/flatlist-rss.log" 2>/dev/null | tail -1) samples=$(wc -l < "$results/flatlist-rss.log" 2>/dev/null | tr -d ' ')"
if [ "$status" -ne 0 ]; then
	echo "FAIL: ios test exit $status; log $results/test.log" >&2
	exit "$status"
fi
echo "PASS: ios counter rotation and press, list and 10000-row FlatList scroll, press, rotate and resume; screenshots $results/screenshots"
