#!/bin/sh
# Neon Refresh transform: the fixture's own build.ms names the module pass, so
# every program here runs from this directory, under -d:refresh, on both targets.
MSC=${MSC:-msc}
cd "$(dirname "$0")"
fail=0
for target in "" "--target=js"; do
	echo "== refresh ${target:-native} boundary.ms"
	"$MSC" test $target -d:refresh boundary.ms || fail=1
done
echo "== refresh native -d:hcr boundary.ms"
"$MSC" test -d:hcr boundary.ms || fail=1
exit $fail
