#!/bin/sh
# SSR parity: the -d:server build writes the same bytes as the tree path, and the same
# bytes on C as on JS. The tree path is the oracle on JS only: a C build without
# -d:server resolves its sheet for a native host and writes inline styles.
# pages.ms prints every page without a byte-exact test, built each way and diffed;
# every test file that renders to a string runs again under -d:server, where its
# exact asserts hold the same bytes.
MSC=${MSC:-msc}
cd "$(dirname "$0")/../.."
out=tests/ssrParity/out
mkdir -p "$out"
rm -f "$out"/*.txt
fail=0
"$MSC" build --target=js tests/ssrParity/pages.ms --output="$out/pages.tree.js" && node "$out/pages.tree.js" > "$out/js.tree.txt" || { echo "FAIL ssrParity js tree: build or run"; fail=1; }
"$MSC" build --target=js -d:server tests/ssrParity/pages.ms --output="$out/pages.server.js" && node "$out/pages.server.js" > "$out/js.server.txt" || { echo "FAIL ssrParity js server: build or run"; fail=1; }
"$MSC" build -d:server tests/ssrParity/pages.ms --output="$out/pages.server" && "$out/pages.server" > "$out/c.server.txt" || { echo "FAIL ssrParity c server: build or run"; fail=1; }
same() {
	if [ ! -s "$out/$1.txt" ] || [ ! -s "$out/$2.txt" ]; then
		return
	elif cmp -s "$out/$1.txt" "$out/$2.txt"; then
		echo "ok   ssrParity pages $2 = $1: $(wc -c < "$out/$1.txt" | tr -d ' ') bytes identical"
	else
		echo "FAIL ssrParity pages: $2 differs from $1"
		diff "$out/$1.txt" "$out/$2.txt" | head -20
		fail=1
	fi
}
same js.tree js.server
same js.server c.server
files=$(grep -rl -e renderToString -e renderToMarkup tests --include="*.test.ms" | grep -v "^tests/browser/" | sort)
for f in $files; do
	echo "== server native $f"
	"$MSC" test -d:server "$f" || fail=1
	echo "== server js $f"
	"$MSC" test --target=js -d:server "$f" || fail=1
done
exit $fail
