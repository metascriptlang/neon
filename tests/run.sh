#!/bin/sh
# Neon test gate — every test file runs native, then --target=js, then the
# browser lane in real Chrome.
# js-lane skips: tests/style/style.test.ms, tests/platform/void.test.ms and
# tests/platform/voidInput.test.ms import the Void platform host, a C-only sibling repo;
# tests/platform/nativeHost, nativeApis, nativeAnimation and nativeLayoutAnimation link the native host against a C mock bridge.
# tests/browser is bound to a real DOM: it has no C lowering and no `document`
# under node, so it runs only through tests/browser/run.sh.
MSC=${MSC:-msc}
cd "$(dirname "$0")/.."
files=$(find tests -name "*.test.ms" -not -path "tests/browser/*" | sort)
fail=0
tests/macros/run.sh || fail=1
tests/apps/run.sh || fail=1
for f in $files; do
	echo "== native $f"
	"$MSC" test "$f" || fail=1
done
for f in $files; do
	case "$f" in
	*style/style.test.ms | *platform/void.test.ms | *platform/voidInput.test.ms | *platform/nativeHost.test.ms | *platform/nativeApis.test.ms | *platform/nativeAnimation.test.ms | *platform/nativeLayoutAnimation.test.ms | *platform/nativeWidgets.test.ms)
		echo "== js skip $f"
		continue
		;;
	esac
	echo "== js $f"
	"$MSC" test --target=js "$f" || fail=1
done
tests/browser/run.sh || fail=1
exit $fail
