#!/bin/sh
# Compile-time contracts of the navigation surface: each file must be REJECTED with the named message.
MSC=${MSC:-msc}
cd "$(dirname "$0")/../.."
fail=0
reject() {
	out=$($MSC check "$1" 2>&1)
	if [ $? -eq 0 ]; then
		echo "FAIL $1: compiled clean, expected a '$2' error"; fail=1
	elif ! echo "$out" | grep -q -- "$2"; then
		echo "FAIL $1: rejected for another reason:"; echo "$out" | head -4; fail=1
	else
		echo "ok   $1: rejected with '$2'"
	fi
}
reject tests/navigation/setParamsFieldTypoRejected.ms "'tba' does not exist in type"
exit $fail
