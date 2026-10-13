#!/bin/sh
# Neon test gate — every test file runs native, then --target=js, then the
# browser lane in real Chrome, then the edge lane in workerd.
# js-lane skips: tests/style/style.test.ms, tests/platform/void.test.ms and
# tests/platform/voidInput.test.ms import the Void platform host, a C-only sibling repo;
# tests/platform/native<Name>.test.ms files link the native host against a C mock bridge.
# tests/browser is bound to a real DOM: it has no C lowering and no `document`
# under node, so it runs only through tests/browser/run.sh.
MSC=${MSC:-msc}
cd "$(dirname "$0")/.."
files=$(find tests -name "*.test.ms" -not -path "tests/browser/*" | sort)
fail=0
tests/macros/run.sh || fail=1
tests/apps/run.sh || fail=1
tests/refresh/run.sh || fail=1
for f in $files; do
	echo "== native $f"
	"$MSC" test "$f" || fail=1
done
for f in $files; do
	case "$f" in
	*style/style.test.ms | *platform/void.test.ms | *platform/voidInput.test.ms | *platform/native[A-Z]*.test.ms)
		echo "== js skip $f"
		continue
		;;
	esac
	echo "== js $f"
	"$MSC" test --target=js "$f" || fail=1
done
case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*)
	echo "== desktop examples/voidWindow.ms"
	"$MSC" build examples/voidWindow.ms --output=out/voidWindow.exe || fail=1
	echo "== desktop examples/windowsNative/app.ms"
	"$MSC" build examples/windowsNative/app.ms --output=out/windowsNative.exe || fail=1
	echo "== desktop examples/windowsNative/text.ms"
	"$MSC" build examples/windowsNative/text.ms --output=out/windowsText.exe || fail=1
	;;
*) echo "== desktop skip examples/voidWindow.ms and examples/windowsNative: Windows-only" ;;
esac
tests/browser/run.sh || fail=1
sh tests/edge/run.sh || fail=1
exit $fail
