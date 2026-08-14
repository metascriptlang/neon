#!/bin/sh
# Neon test gate — every test file runs native, then --target=js.
# js-lane skips (measured 2026-08-14):
#   style/voidHost — Void platform host, C-only sibling repo
#   direct — direct-emission arc in flight; enable when it lands
MSC=${MSC:-msc}
cd "$(dirname "$0")/.."
fail=0
for f in $(find tests -name "*.test.ms" | sort); do
	echo "== native $f"
	"$MSC" test "$f" || fail=1
done
for f in $(find tests -name "*.test.ms" | sort); do
	case "$f" in
	*render/style.test.ms | *render/voidHost.test.ms | *render/direct.test.ms)
		echo "== js skip $f"
		continue
		;;
	esac
	echo "== js $f"
	"$MSC" test "$f" --target=js || fail=1
done
exit $fail
