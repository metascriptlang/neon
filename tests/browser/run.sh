#!/bin/sh
# Neon browser lane — the same `test "…" { assert … }` files every other lane runs,
# executed against a real DOM in real Chrome instead of a mock host.
#
# `msc test --target=js` emits an ES-module tree under out/debug beside the test file
# and then runs it under node, where `document` does not exist; that run is expected
# to fail and its status is discarded. The artifacts it leaves are what Chrome loads.
# Setup once per checkout: npm install --prefix tests/browser
set -e
cd "$(dirname "$0")/../.."
MSC=${MSC:-msc}
PORT=${NEON_BROWSER_PORT:-8733}

PW=${NEON_PLAYWRIGHT:-$PWD/tests/browser/node_modules/playwright-core/index.mjs}
if [ ! -f "$PW" ]; then
	echo "playwright-core not found at $PW — run: npm install --prefix tests/browser" >&2
	exit 2
fi

files=$*
if [ -z "$files" ]; then files=$(find tests/browser -name "*.test.ms" -not -path "*/node_modules/*" | sort); fi

node tests/browser/serve.mjs "$PWD" "$PORT" &
server=$!
trap 'kill $server 2>/dev/null' EXIT INT TERM

fail=0
for f in $files; do
	echo "== browser $f"
	out="$(dirname "$f")/out/debug"
	rm -f "$out/_test/main.js"
	"$MSC" test --target=js "$f" >/dev/null 2>&1 || true
	if [ ! -f "$out/_test/main.js" ]; then
		echo "   COMPILE FAILED — no test bundle emitted at $out/_test/main.js; run: $MSC test --target=js $f" >&2
		fail=1
		continue
	fi
	cp tests/browser/page.html "$out/neon-test.html"
	node tests/browser/runner.mjs "$PW" "$PORT" "$f" "$out/neon-test.html" || fail=1
done
exit $fail
