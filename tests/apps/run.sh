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
	out=$(NO_COLOR=1 "$MSC" run --target=js "$1" 2>&1 | grep '^<app>')
	if [ "$out" = "$golden" ]; then
		echo "ok   js $1"
	else
		echo "FAIL js $1: got"
		echo "$out" | head -4
		fail=1
	fi
}

warnings='initialScrollIndex "15" is not valid (list has 10 items)
initialScrollIndex "-1" is not valid (list has 3 items)
FlatList: Both ListItemComponent and renderItem props are present. ListItemComponent will take precedence over renderItem.'

expect_warnings() {
	for target in "" "--target=js"; do
		out=$(NO_COLOR=1 "$MSC" run $target "$1" 2>&1 >/dev/null | grep -E '^(initialScrollIndex|FlatList: Both)')
		if [ "$out" = "$warnings" ]; then
			echo "ok   ${target:-native} $1"
		else
			echo "FAIL ${target:-native} $1: stderr warnings were"
			echo "$out" | head -4
			fail=1
		fi
	done
}

bundles=$(mktemp -d)
trap 'rm -rf "$bundles"' EXIT

expect_bundle() {
	bad=0
	NO_COLOR=1 "$MSC" build --target=js --output="$bundles/$1.js" "tests/apps/$1.ms" >/dev/null 2>&1
	for m in $2; do
		grep -q "^// --- Module: .*/src/$m ---\$" "$bundles/$1.js" 2>/dev/null || { echo "FAIL bundle $1: missing $m"; bad=1; }
	done
	for m in $3; do
		grep -q "^// --- Module: .*/src/$m ---\$" "$bundles/$1.js" 2>/dev/null && { echo "FAIL bundle $1: carries $m"; bad=1; }
	done
	[ $bad = 0 ] && echo "ok   bundle $1" || fail=1
}

# Native counts the loaded segments: LINKEDIT shifts by a few bytes between identical builds.
expect_size() {
	if [ "$2" = js ]; then
		NO_COLOR=1 "$MSC" build --target=js --output="$bundles/$1.size.js" "tests/apps/$1.ms" >/dev/null 2>&1
		got=$(wc -c < "$bundles/$1.size.js" 2>/dev/null | tr -d ' ')
	else
		NO_COLOR=1 "$MSC" build --release --output="$bundles/$1.size" "tests/apps/$1.ms" >/dev/null 2>&1
		got=$(size -m "$bundles/$1.size" 2>/dev/null | awk '/^Segment __(TEXT|DATA_CONST|DATA):/ { n += $3 } END { print n + 0 }')
	fi
	if [ -z "$got" ] || [ "$got" = 0 ]; then
		echo "FAIL size $1 $2: did not build"
		fail=1
	elif [ "$got" -gt "$3" ]; then
		echo "FAIL size $1 $2: $got bytes, budget $3 (+$((got - $3))); raise the budget in the commit that grows it"
		fail=1
	elif [ "$got" -lt "$3" ]; then
		echo "ok   size $1 $2: $got bytes, $(($3 - got)) under budget $3; lower the budget"
	else
		echo "ok   size $1 $2: $got bytes"
	fi
}

mangled() {
	printf '%s' "$1" | perl -pe 's/([A-Z])/ord($1)/ge; s#/#Z#g'
}

expect_native_modules() {
	NO_COLOR=1 "$MSC" build --release --output="$bundles/$1.syms" "tests/apps/$1.ms" >/dev/null 2>&1
	syms=$(nm --defined-only "$bundles/$1.syms" 2>/dev/null)
	bad=0
	[ -n "$syms" ] || { echo "FAIL modules $1: did not build"; fail=1; return; }
	for m in $2; do
		echo "$syms" | grep -q "ZsrcZ$(mangled "$m")O" || { echo "FAIL modules $1: missing $m"; bad=1; }
	done
	for m in $3; do
		echo "$syms" | grep -q "ZsrcZ$(mangled "$m")O" && { echo "FAIL modules $1: carries $m"; bad=1; }
	done
	[ $bad = 0 ] && echo "ok   modules $1" || fail=1
}

expect_output tests/apps/localSignalApp.ms
expect_output tests/apps/moduleSignalApp.ms
expect_warnings tests/apps/listWarnApp.ms
expect_bundle bundlePlainApp "platform/browser/dom" "platform/browser/media platform/browser/camera platform/browser/captureServices platform/browser/svg components/svg/markup components/svg/scene platform/browser/notifications api/notifications"
expect_bundle bundleSvgApp "platform/browser/svg components/svg/markup" "platform/browser/media platform/browser/camera platform/browser/captureServices"
expect_native_modules bundleTerminalApp "platform/terminal/host" "components/svg/scene platform/native/host platform/browser/dom"
expect_size bundlePlainApp js 972693
expect_size bundleTerminalApp native 657232
exit $fail
