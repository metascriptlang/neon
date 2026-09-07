#!/bin/sh
# Neon test gate — every test file runs native, then --target=js, then the
# browser lane in real Chrome.
# js-lane skips (measured 2026-08-14):
#   style/void — Void platform host, C-only sibling repo
#   direct — direct-emission arc in flight; enable when it lands
# tests/browser is bound to a real DOM: it has no C lowering and no `document`
# under node, so it runs only through tests/browser/run.sh.
MSC=${MSC:-msc}
cd "$(dirname "$0")/.."
files=$(find tests -name "*.test.ms" -not -path "tests/browser/*" | sort)
fail=0
for f in $files; do
	echo "== native $f"
	"$MSC" test "$f" || fail=1
done
for f in $files; do
	case "$f" in
	*style/style.test.ms | *platform/void.test.ms | *render/direct.test.ms)
		echo "== js skip $f"
		continue
		;;
	esac
	echo "== js $f"
	"$MSC" test "$f" --target=js || fail=1
done
tests/browser/run.sh || fail=1
exit $fail
