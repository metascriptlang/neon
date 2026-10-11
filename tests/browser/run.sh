#!/bin/sh
# Neon browser lane — the same `test "…" { assert … }` files every other lane runs,
# executed against a real DOM in real Chrome instead of a mock host.
#
# `msc test --target=js` emits an ES-module tree under out/debug in the project root, or
# beside the test file where the compiler cannot prefix the entry with that root, and then
# runs it under node, where `document` does not exist; that run is expected to fail and
# its status is discarded. The artifacts it leaves are what Chrome loads.
# Setup once per checkout: npm install --prefix tests/browser
set -e
cd "$(dirname "$0")/../.."
MSC=${MSC:-msc}

PW=${NEON_PLAYWRIGHT:-$PWD/tests/browser/node_modules/playwright-core/index.mjs}
if [ ! -f "$PW" ]; then
	echo "playwright-core not found at $PW — run: npm install --prefix tests/browser" >&2
	exit 2
fi

files=$*
if [ -z "$files" ]; then files=$(find tests/browser -name "*.test.ms" -not -path "*/node_modules/*" | sort); fi

portfile=$(mktemp)
node tests/browser/serve.mjs "$PWD" "${NEON_BROWSER_PORT:-0}" > "$portfile" &
server=$!
trap 'kill $server 2>/dev/null; rm -f "$portfile"' EXIT INT TERM
while [ ! -s "$portfile" ]; do
	if ! kill -0 $server 2>/dev/null; then
		echo "the browser test server did not start; nothing ran" >&2
		exit 2
	fi
	sleep 0.1
done
PORT=$(head -1 "$portfile")

fail=0
for f in $files; do
	echo "== browser $f"
	root_out=out/debug
	beside_out="$(dirname "$f")/out/debug"
	rm -f "$root_out/_test/main.js" "$beside_out/_test/main.js"
	"$MSC" test --target=js "$f" >/dev/null 2>&1 || true
	out=""
	for candidate in "$root_out" "$beside_out"; do
		if [ -f "$candidate/_test/main.js" ]; then out="$candidate"; break; fi
	done
	if [ -z "$out" ]; then
		echo "   COMPILE FAILED — no test bundle emitted at $root_out or $beside_out; run: $MSC test --target=js $f" >&2
		fail=1
		continue
	fi
	cp tests/browser/page.html "$out/neon-test.html"
	node tests/browser/runner.mjs "$PW" "$PORT" "$f" "$out/neon-test.html" || fail=1
done
exit $fail
