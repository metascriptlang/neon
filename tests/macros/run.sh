#!/bin/sh
# Compile-time contracts of the UI macros: each file here must be REJECTED with
# the named message. A clean compile means the macro swallowed something.
MSC=${MSC:-msc}
cd "$(dirname "$0")/../.."
fail=0
reject_on() {
	target=$1
	out=$("$MSC" build $target "$2" 2>&1)
	if [ $? -eq 0 ]; then
		echo "FAIL $2 ${target:-native}: compiled clean — expected a '$3' error"
		fail=1
	elif ! echo "$out" | grep -q -- "$3"; then
		echo "FAIL $2 ${target:-native}: rejected for another reason:"
		echo "$out" | head -4
		fail=1
	else
		echo "ok   $2 ${target:-native}: rejected with '$3'"
	fi
}
expect_reject() { reject_on --target=js "$1" "$2"; }
expect_reject_both() { reject_on --target=js "$1" "$2"; reject_on "" "$1" "$2"; }
expect_reject tests/macros/spreadMapRejected.ms "a spread needs an object type with named fields"
expect_reject tests/macros/spreadCallRejected.ms "a spread needs a variable or a field, not an expression"
expect_reject tests/macros/spreadChildrenRejected.ms "children cannot come from a spread"
expect_reject tests/macros/spreadNullHandlerRejected.ms "a nullable onPress handler is not supported yet"
expect_reject tests/macros/spreadNullStyleRejected.ms "a nullable style is not supported yet"
expect_reject tests/macros/mapIndexRowRejected.ms "a .map row that takes an index is written <For each={xs}>"
expect_reject tests/macros/mapNamedRowRejected.ms "Argument type mismatch in 'map' arg 0"
expect_reject tests/macros/accessorNominal.ms "is not assignable to type 'Accessor<number>'"
expect_reject tests/macros/emptyLayerRejected.ms "a style layer array needs at least one layer"
expect_reject tests/macros/refLiteralRejected.ms "arg 1: got string, expected function"
expect_reject tests/macros/refLiteralRootRejected.ms "arg 1: got string, expected function"
expect_reject tests/macros/refEmptyArrayRejected.ms "a ref array needs at least one ref"
expect_reject tests/macros/refArrayEntryRejected.ms "Type .string. is not assignable to type .function . null."
expect_reject tests/macros/optChangeTextTemplateRejected.ms "a nullable onChangeText handler is not supported yet"
expect_reject tests/macros/optChangeTextFlatRejected.ms "a nullable onChangeText handler is not supported yet"
expect_reject tests/macros/componentUnknownPropRejected.ms "<Badge> has no prop 'lable'"
expect_reject tests/macros/componentMixedAccessorRejected.ms "prop 'value' of <Count> mixes Accessor with another type"
expect_reject tests/macros/componentNotInScopeRejected.ms "<Missing> is not a component in scope"
expect_reject tests/macros/componentSlotRequiredPropsRejected.ms "a node slot component requires prop 'title': pass an element with props instead"
expect_reject tests/macros/contextProviderDotRejected.ms "<Tone.Provider> names no field 'Provider'"
expect_reject tests/macros/contextProviderValueMissingRejected.ms "<Tone> needs a value prop"
expect_reject tests/macros/contextProviderValueTypeRejected.ms "Type 'int32' is not assignable to type 'string'"
expect_reject tests/macros/forKeyedComputedRejected.ms "<For keyed> takes true, false or a key function, written in place"
expect_reject tests/macros/showKeyedComputedRejected.ms "<Show keyed> takes true or false, written in place"
expect_reject tests/macros/showFunctionArityRejected.ms "a <Show> function child takes one parameter, the narrowed value"
expect_reject tests/macros/showWhenMissingRejected.ms "<Show> requires the 'when' prop"
expect_reject_both tests/macros/omittedAccessorPropRejected.ms "field 'suffix' must be initialized"
expect_reject tests/macros/matchWhenRejected.ms "<Match> takes no 'when': Solid's <Match when> is <Case when> here"
expect_reject tests/macros/caseOutsideMatchRejected.ms "<Case> is only a direct child of <Match>: write <Match>"
expect_reject tests/macros/caseUnderShowRejected.ms "<Case> is only a direct child of <Match>: write <Match>"
expect_reject tests/macros/matchChildRejected.ms "<Match> holds only <Case> branches: write the branch as <Case"
expect_reject tests/macros/caseKeyedComputedRejected.ms "<Case keyed> takes true or false, written in place"
expect_reject_both tests/macros/componentReadCallRejected.ms "STRICT_READ_UNTRACKED. Reactive value .props.n. read directly in <Count>"
expect_reject_both tests/macros/componentReadValueOfRejected.ms "STRICT_READ_UNTRACKED. Reactive value .props.n. read directly in <Count>"
expect_reject_both tests/macros/componentWriteInMemoRejected.ms "REACTIVE_WRITE_IN_OWNED_SCOPE. Writing to reactive state with .setCount. inside a computation of <Count>"
expect_reject_both tests/macros/moduleSetterWriteInMemoRejected.ms "REACTIVE_WRITE_IN_OWNED_SCOPE. Writing to reactive state with .setCount. inside a computation of <Count>"
expect_reject_both tests/macros/moduleSetterWriteInEffectRejected.ms "REACTIVE_WRITE_IN_OWNED_SCOPE. Writing to reactive state with .setCount. inside a computation of <Count>"
expect_reject_both tests/macros/componentWriteInHoleRejected.ms "REACTIVE_WRITE_IN_OWNED_SCOPE. Writing to reactive state with .setCount. inside a computation of <Count>"
exit $fail
