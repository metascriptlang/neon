#!/bin/sh
# Neon Refresh transform: the fixture's own build.ms names the module pass, so
# every program here runs from this directory, under -d:refresh, on both targets.
MSC=${MSC:-msc}
cd "$(dirname "$0")"
fail=0
for file in boundary.ms state.ms; do
	for target in "" "--target=js"; do
		echo "== refresh ${target:-native} $file"
		"$MSC" test $target -d:refresh $file || fail=1
	done
	echo "== refresh native -d:hcr $file"
	"$MSC" test -d:hcr $file || fail=1
done
exit $fail
