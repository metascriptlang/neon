#!/bin/sh
# Neon test gate — every test file runs native, then --target=js, then the
# browser lane in real Chrome.
# js-lane skips: tests/style/style.test.ms and tests/platform/void.test.ms import
# the Void platform host, a C-only sibling repo; tests/platform/nativeHost.test.ms
# links the native host against a C mock bridge.
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
	*style/style.test.ms | *platform/void.test.ms | *platform/nativeHost.test.ms)
		echo "== js skip $f"
		continue
		;;
	esac
	echo "== js $f"
	"$MSC" test "$f" --target=js || fail=1
done
tests/browser/run.sh || fail=1
exit $fail
