#!/bin/sh
# A Neon iOS app awaiting one 600 KB WebSocket message with no timer pending must receive it
# without a touch: the UI loop wakes on the runtime's I/O selector, not only on timers.
set -eu
cd "$(dirname "$0")/../.."
neon=$PWD
ION=${ION:-$neon/../ion}
PORT=47913
SIZE=600000
DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
results=$(mktemp -d /private/tmp/neon-io-wake.XXXXXX)
echo "== io-wake results=$results"

step() {
	name=$1
	shift
	if ! "$@" > "$results/$name.log" 2>&1; then
		echo "FAIL: io-wake $name; log $results/$name.log" >&2
		tail -20 "$results/$name.log" >&2
		exit 1
	fi
}

mkdir -p "$results/home"
step install-ion env HOME="$results/home" msc install -g "@metascript/ion@file:$ION"
ion() { HOME="$results/home" "$results/home/.metascript/bin/ion" "$@"; }
step generate ion generate tests/ios/ioWake/project.ms "$results/xcode"
step build xcodebuild -project "$results/xcode/NeonIoWake.xcodeproj" -target NeonIoWake \
	-configuration Debug -sdk iphonesimulator -jobs 1 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
	SYMROOT="$results/products" OBJROOT="$results/objects" \
	CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

runtime=$(xcrun simctl list runtimes available | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)$/\1/p' | tail -1)
if [ -z "$runtime" ]; then
	echo "FAIL: io-wake needs an installed iOS simulator runtime" >&2
	exit 1
fi
device=$(xcrun simctl create "Neon io-wake" "$DEVICE_TYPE" "$runtime")
server=
cleanup() {
	[ -n "$server" ] && kill "$server" 2>/dev/null
	xcrun simctl shutdown "$device" >/dev/null 2>&1
	xcrun simctl delete "$device" >/dev/null 2>&1
}
trap cleanup EXIT INT TERM
step boot xcrun simctl bootstatus "$device" -b
step install xcrun simctl install "$device" "$results/products/Debug-iphonesimulator/NeonIoWake.app"

python3 -I tests/ios/ioWake/server.py "$PORT" "$SIZE" 2 > "$results/server.log" 2>&1 &
server=$!
sleep 1
xcrun simctl launch --console-pty "$device" dev.neon.NeonIoWake > "$results/app.log" 2>&1 &
for _ in $(seq 1 20); do
	grep -q "NEON_IO_WAKE" "$results/app.log" && break
	sleep 1
done
cat "$results/server.log"
if ! grep -q "NEON_IO_WAKE received $SIZE" "$results/app.log"; then
	echo "FAIL: io-wake; app log $results/app.log:" >&2
	tail -5 "$results/app.log" >&2
	exit 1
fi
sleep 5
app=$(pgrep -x NeonIoWake | head -1)
cpu=$(ps -o %cpu= -p "$app" | tr -d ' ')
xcrun simctl terminate "$device" dev.neon.NeonIoWake >/dev/null 2>&1 || true
if [ "${cpu%.*}" -ge 10 ]; then
	echo "FAIL: io-wake idle app uses ${cpu}% CPU; the selector watch spins" >&2
	exit 1
fi
echo "PASS: io-wake received $SIZE bytes with no timer pending; idle CPU ${cpu}%"
