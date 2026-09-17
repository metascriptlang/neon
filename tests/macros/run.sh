#!/bin/sh
# Compile-time contracts of the UI macros: each file here must be REJECTED with
# the named message. A clean compile means the macro swallowed something.
MSC=${MSC:-msc}
cd "$(dirname "$0")/../.."
fail=0
expect_reject() {
	out=$("$MSC" build --target=js "$1" 2>&1)
	if [ $? -eq 0 ]; then
		echo "FAIL $1: compiled clean — expected a '$2' error"
		fail=1
	elif ! echo "$out" | grep -q -- "$2"; then
		echo "FAIL $1: rejected for another reason:"
		echo "$out" | head -4
		fail=1
	else
		echo "ok   $1: rejected with '$2'"
	fi
}
expect_reject tests/macros/spreadRejected.ms "spread attributes are not supported"
expect_reject tests/macros/spreadInContainerRejected.ms "spread attributes are not supported"
expect_reject tests/macros/fragmentInExprRejected.ms "a fragment inside an expression is not supported"
expect_reject tests/macros/fragmentInExprDirectRejected.ms "a fragment inside an expression is not supported"
expect_reject tests/macros/fragmentDirectRootRejected.ms "a fragment has no single host node to return"
expect_reject tests/macros/accessorNominal.ms "is not assignable to type 'Accessor<number>'"
expect_reject tests/macros/emptyLayerRejected.ms "a style layer array needs at least one layer"
expect_reject tests/macros/emptyLayerDirectRejected.ms "a style layer array needs at least one layer"
expect_reject tests/macros/reactiveLayerFieldRejected.ms "a reactive style field inside a layer array is not supported yet"
expect_reject tests/macros/reactiveLayerFieldDirectRejected.ms "a reactive style field inside a layer array is not supported yet"
expect_reject tests/macros/reactiveLayerFieldMixedRejected.ms "a reactive style field inside a layer array is not supported yet"
expect_reject tests/macros/reactiveLayerFieldMixedDirectRejected.ms "a reactive style field inside a layer array is not supported yet"
expect_reject tests/macros/refLiteralRejected.ms "arg 1: got string, expected function"
expect_reject tests/macros/refLiteralDirectRejected.ms "arg 1: got string, expected function"
expect_reject tests/macros/refLiteralDirectRootRejected.ms "arg 1: got string, expected function"
exit $fail
