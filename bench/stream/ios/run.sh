#!/bin/sh
# S1 on iOS: build bench/stream Release, install, fling it under XCTest scroll signpost metrics, print them.
# Usage: bench/stream/ios/run.sh <device-udid | sim> <label>   (from the Neon checkout; ION defaults to ../ion)
set -eu
cd "$(dirname "$0")/../../.."
target=$1
label=$2
ION=${ION:-$PWD/../ion}
r=/private/tmp/neon-bench-stream/$label-$(date +%H%M%S)
mkdir -p "$r/home"
step() { n=$1; shift; if ! "$@" > "$r/$n.log" 2>&1; then echo "FAIL $n: $r/$n.log"; tail -15 "$r/$n.log"; exit 1; fi; }
step install-ion env HOME="$r/home" msc install -g "@metascript/ion@file:$ION"
step generate env HOME="$r/home" "$r/home/.metascript/bin/ion" generate bench/stream/ios/project.ms "$r/xcode"
if [ "$target" = sim ]; then
	runtime=$(xcrun simctl list runtimes available | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)$/\1/p' | tail -1)
	device=$(xcrun simctl create "Neon stream bench" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime")
	trap 'xcrun simctl shutdown "$device" >/dev/null 2>&1; xcrun simctl delete "$device" >/dev/null 2>&1' EXIT INT TERM
	step build xcodebuild -project "$r/xcode/NeonStream.xcodeproj" -target NeonStream -configuration Release -sdk iphonesimulator -jobs 4 \
		ARCHS=arm64 ONLY_ACTIVE_ARCH=YES SYMROOT="$r/products" OBJROOT="$r/objects" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
	step boot xcrun simctl bootstatus "$device" -b
	step install xcrun simctl install "$device" "$r/products/Release-iphonesimulator/NeonStream.app"
	sign=""
else
	device=$target
	sign="CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-4R7EAZY462} CODE_SIGN_IDENTITY=Apple Development"
	step build xcodebuild -project "$r/xcode/NeonStream.xcodeproj" -target NeonStream -configuration Release -sdk iphoneos -jobs 4 \
		ARCHS=arm64 ONLY_ACTIVE_ARCH=YES SYMROOT="$r/products" OBJROOT="$r/objects" -allowProvisioningUpdates $sign build
	xcrun devicectl device uninstall app --device "$device" dev.neon.NeonStream > "$r/uninstall.log" 2>&1 || true
	step install xcrun devicectl device install app --device "$device" "$r/products/Release-iphoneos/NeonStream.app"
fi
# shellcheck disable=SC2086
step test xcodebuild test -project tests/ios/counter.xcodeproj -scheme CounterUITests -only-testing:CounterUITests/StreamBenchUITests \
	-destination "id=$device" -derivedDataPath "$r/derived" -resultBundlePath "$r/result.xcresult" $sign
xcrun xcresulttool get test-results metrics --path "$r/result.xcresult" > "$r/metrics.json" 2>"$r/metrics.err" || true
python3 - "$r/metrics.json" "$label" <<'PY'
import json, sys, statistics
data = json.load(open(sys.argv[1]))
def walk(o):
    if isinstance(o, dict):
        if "displayName" in o and "measurements" in o:
            yield o
        for v in o.values(): yield from walk(v)
    elif isinstance(o, list):
        for v in o: yield from walk(v)
for m in walk(data):
    vals = m["measurements"]
    print(f"{sys.argv[2]} | {m['displayName']} ({m.get('unitOfMeasurement','')}) | median {statistics.median(vals):.3f} | runs {', '.join(f'{v:.3f}' for v in vals)}")
PY
echo "results: $r"
