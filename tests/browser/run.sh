#!/bin/sh
# Neon browser lane — the same `test "…" { assert … }` files every other lane runs,
# executed against a real DOM in real Chrome instead of a mock host.
#
# `msc test --target=js` emits an ES-module tree under out/debug and then runs it
# under node, where `document` does not exist; that run is expected to fail and its
# status is discarded. The artifacts it leaves are what Chrome loads.
set -e
cd "$(dirname "$0")/../.."
MSC=${MSC:-msc}
PORT=${NEON_BROWSER_PORT:-8733}
OUT=out/debug

PW=${NEON_PLAYWRIGHT:-$PWD/examples/vite-counter/node_modules/playwright/index.mjs}
if [ ! -f "$PW" ]; then
	echo "playwright not found at $PW — set NEON_PLAYWRIGHT to its index.mjs" >&2
	exit 2
fi

files=$*
if [ -z "$files" ]; then files=$(find tests/browser -name "*.test.ms" | sort); fi

python3 -m http.server "$PORT" --directory "$OUT" >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null' EXIT INT TERM

fail=0
for f in $files; do
	echo "== browser $f"
	rm -f "$OUT/_test/main.js"
	"$MSC" test --target=js "$f" >/dev/null 2>&1 || true
	if [ ! -f "$OUT/_test/main.js" ]; then
		echo "   COMPILE FAILED — no test bundle emitted; run: $MSC test --target=js $f" >&2
		fail=1
		continue
	fi
	cp tests/browser/page.html "$OUT/neon-test.html"
	node tests/browser/runner.mjs "$PW" "$PORT" "$f" || fail=1
done
exit $fail
