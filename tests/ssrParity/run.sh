#!/bin/sh
# SSR lane: the only lane that renders to a string, because only a -d:server build can.
# pages.ms prints every page without a byte-exact test, built for JS and for C and held to
# the recorded bytes in pages.expected.txt, the way Solid's server specs write artifacts
# under test/harness/__artifacts__ that a changed render must re-record; the C server must
# also write the JS server's bytes. Every test file that renders to a string runs under
# -d:server on both backends, where its exact asserts hold the same bytes.
MSC=${MSC:-msc}
cd "$(dirname "$0")/../.."
out=tests/ssrParity/out
mkdir -p "$out"
rm -f "$out"/*.txt
fail=0
"$MSC" build --target=js -d:server tests/ssrParity/pages.ms --output="$out/pages.server.js" && node "$out/pages.server.js" > "$out/js.server.txt" || { echo "FAIL ssrParity js server: build or run"; fail=1; }
"$MSC" build -d:server tests/ssrParity/pages.ms --output="$out/pages.server" && "$out/pages.server" > "$out/c.server.txt" || { echo "FAIL ssrParity c server: build or run"; fail=1; }
same() {
	if [ ! -s "$2" ] || [ ! -s "$3" ]; then
		return
	elif cmp -s "$2" "$3"; then
		echo "ok   ssrParity pages $1: $(wc -c < "$2" | tr -d ' ') bytes identical"
	else
		echo "FAIL ssrParity pages $1"
		diff "$2" "$3" | head -20
		if [ -n "$4" ]; then echo "     if the change is intended, re-record: $4"; fi
		fail=1
	fi
}
same "js server = recorded" tests/ssrParity/pages.expected.txt "$out/js.server.txt" "cp $out/js.server.txt tests/ssrParity/pages.expected.txt"
same "c server = js server" "$out/js.server.txt" "$out/c.server.txt"
needs() {
	if log=$("$MSC" build $2 "tests/ssrParity/$1.ms" --output="$out/$1" 2>&1); then
		echo "FAIL ssrParity $1 $3: a plain build must not compile"
		fail=1
	elif echo "$log" | grep -q "renderTo[A-Za-z]* needs a -d:server build"; then
		echo "ok   ssrParity $1 $3: a plain build names the case"
	else
		echo "FAIL ssrParity $1 $3: a plain build failed without naming the case"
		echo "$log" | head -5
		fail=1
	fi
}
for pin in needsServer needsServerBarrel needsServerPrelude; do
	needs $pin "" c
	needs $pin "--target=js" js
done
files=$(grep -rl -e renderToString -e renderToMarkup tests --include="*.test.ms" | grep -v "^tests/browser/" | sort)
for f in $files; do
	echo "== server native $f"
	"$MSC" test -d:server "$f" || fail=1
	echo "== server js $f"
	"$MSC" test --target=js -d:server "$f" || fail=1
done
exit $fail
