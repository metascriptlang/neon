#!/bin/sh
# Metal device programs: each opens a Void window, checks its frames on the GPU and exits non-zero on a failed check.
MSC=${MSC:-msc}
cd "$(dirname "$0")/../.."
mkdir -p out/device
fail=0
for f in tests/device/*.ms; do
	name=$(basename "$f" .ms)
	echo "== device $f"
	{ "$MSC" build "$f" --output="out/device/$name" && "out/device/$name"; } || fail=1
done
exit $fail
