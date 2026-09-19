#!/bin/sh
# Programs, not test blocks: every file here is built and RUN the way a user's app
# is, then its stdout is compared. A test block declares its signals inside itself,
# so nothing else in the suite covers module-level state — the shape KNOWN-ISSUES
# L46 breaks on C.
MSC=${MSC:-msc}
cd "$(dirname "$0")/../.."
fail=0
golden='<app><div>count=0</div></app>
<app><div>count=1</div></app>'

expect_output() {
	for target in "" "--target=js"; do
		out=$(NO_COLOR=1 "$MSC" run "$1" $target 2>&1 | grep '^<app>')
		if [ "$out" = "$golden" ]; then
			echo "ok   ${target:-native} $1"
		else
			echo "FAIL ${target:-native} $1: got"
			echo "$out" | head -4
			fail=1
		fi
	done
}

# Red until the named issue is fixed. Flips the lane red the day it passes, so the
# case gets promoted to expect_output instead of quietly guarding nothing.
expect_known_red() {
	out=$(NO_COLOR=1 "$MSC" run "$1" 2>&1 | grep '^<app>')
	if [ "$out" = "$golden" ]; then
		echo "FAIL native $1: passes now — $2 is fixed, promote this to expect_output"
		fail=1
	else
		echo "red  native $1: known, $2"
	fi
	out=$(NO_COLOR=1 "$MSC" run "$1" --target=js 2>&1 | grep '^<app>')
	if [ "$out" = "$golden" ]; then
		echo "ok   js $1"
	else
		echo "FAIL js $1: got"
		echo "$out" | head -4
		fail=1
	fi
}

expect_output tests/apps/localSignalApp.ms
expect_known_red tests/apps/moduleSignalApp.ms "recompiler KNOWN-ISSUES L46"
exit $fail
