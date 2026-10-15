#!/bin/sh
# SSR parity: the -d:server build writes the same bytes as the tree path.
# pages.ms prints every page without a byte-exact test, built both ways and diffed;
# every test file that renders to a string runs again under -d:server, where its
# exact asserts hold the same bytes.
MSC=${MSC:-msc}
cd "$(dirname "$0")/../.."
out=tests/ssrParity/out
mkdir -p "$out"
fail=0
for target in c js; do
	built=1
	for mode in tree server; do
		flag=""
		[ "$mode" = server ] && flag="-d:server"
		bin="$out/pages.$mode"
		if [ "$target" = js ]; then
			"$MSC" build --target=js $flag tests/ssrParity/pages.ms --output="$bin.js" && node "$bin.js" > "$out/$target.$mode.txt"
		else
			"$MSC" build $flag tests/ssrParity/pages.ms --output="$bin" && "$bin" > "$out/$target.$mode.txt"
		fi
		[ $? -eq 0 ] || { echo "FAIL ssrParity $target $mode: build or run"; fail=1; built=0; }
	done
	if [ $built -eq 0 ]; then
		continue
	elif cmp -s "$out/$target.tree.txt" "$out/$target.server.txt"; then
		echo "ok   ssrParity pages $target: $(wc -c < "$out/$target.tree.txt" | tr -d ' ') bytes identical"
	else
		echo "FAIL ssrParity pages $target: -d:server differs from the tree path"
		diff "$out/$target.tree.txt" "$out/$target.server.txt" | head -20
		fail=1
	fi
done
files=$(grep -rl -e renderToString -e renderToMarkup tests --include="*.test.ms" | grep -v "^tests/browser/" | sort)
for f in $files; do
	echo "== server native $f"
	"$MSC" test -d:server "$f" || fail=1
	echo "== server js $f"
	"$MSC" test --target=js -d:server "$f" || fail=1
done
exit $fail
