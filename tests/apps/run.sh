#!/bin/sh
# Programs, not test blocks: every file here is built and RUN the way a user's app
# is, then its stdout is compared. A test block declares its signals inside itself,
# so nothing else in the suite covers module-level state.
MSC=${MSC:-msc}
cd "$(dirname "$0")/../.."
fail=0
golden='<app><div>count=0</div></app>
<app><div>count=1</div></app>'

expect_output() {
	for target in "" "--target=js"; do
		out=$(NO_COLOR=1 "$MSC" run $target "$1" 2>&1 | grep '^<app>')
		if [ "$out" = "$golden" ]; then
			echo "ok   ${target:-native} $1"
		else
			echo "FAIL ${target:-native} $1: got"
			echo "$out" | head -4
			fail=1
		fi
	done
}

expect_output tests/apps/localSignalApp.ms
expect_output tests/apps/moduleSignalApp.ms
exit $fail
