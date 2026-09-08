#!/bin/sh
# Every place a style field must be named agrees with STYLE_TABLE. Interim gate
# until the four core lists are generated from the table (blocked on bug 8).
cd "$(dirname "$0")/../.."
between() { awk -v a="$2" -v b="$3" '$0 ~ a {f=1; next} f && $0 ~ b {exit} f' "$1"; }
table=$(between src/macros/style/fields.ms '^export const STYLE_TABLE' '^\];' | sed -n -E 's/^\t\["([A-Za-z]+)".*/\1/p' | sort)
lists="interface|src/render/style.ms|^export interface Style \\{|^\\}|/^\t(css|cssId): /d; s/^\t([A-Za-z]+): .*/\\1/p
setStyleField|src/render/style.ms|^export function setStyleField|^\\}|s/^\t\t\"([A-Za-z]+)\" =>.*/\\1/p
mergeStyle|src/render/style.ms|^export function mergeStyle|^\\}|s/^\t\t([A-Za-z]+): over\\..*/\\1/p
styleToCss|src/render/css.ms|^export function styleToCss|^\\}|s/.*css[A-Za-z]+\\(\"([A-Za-z]+)\".*/\\1/p
CssStyle|src/platform/browser/dom.ms|^extern class CssStyle|^\\}|/^\tcssText: /d; s/^\t([A-Za-z]+): cstring;.*/\\1/p"
fail=0
printf '%-14s %s\n' STYLE_TABLE "$(echo "$table" | wc -l | tr -d ' ')"
echo "$lists" | while IFS='|' read -r label file from to pat; do
	got=$(between "$file" "$from" "$to" | sed -n -E "$pat" | sort)
	n=$(echo "$got" | wc -l | tr -d ' ')
	if [ "$got" = "$table" ]; then
		printf '%-14s %s\n' "$label" "$n"
	else
		printf '%-14s %s  MISMATCH\n' "$label" "$n"
		tmp=$(mktemp -d)
		echo "$table" > "$tmp/table"; echo "$got" > "$tmp/list"
		diff "$tmp/table" "$tmp/list" | grep -E '^[<>]' | sed 's/^</  only in table: /; s/^>/  only in list:  /'
		rm -rf "$tmp"
		exit 1
	fi
done || fail=1
exit $fail
