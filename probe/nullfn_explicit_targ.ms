// OPEN sibling — explicit-type-arg arrow degeneration (pinned 2026-07-22).
//
// EXPECTED (bug): checker error "Argument type mismatch in 'apply' arg 0: got
//   function, expected Maybe_fn_fnnumbernumber17" — with explicit `<number>` the
//   arrow is checked against the RAW (pre-substitution) formal and its type
//   degenerates to a bare "function".
// Same checkArg-then-bind family as nullfn_generic_arg_notlowered; distinct from
//   gap-2 (which fixed the WRAP type once binding is known). Trace target: the
//   arrow must be checked against the INSTANTIATED formal (Nim implicitConv
//   getInstantiatedType, sigmatch.nim:2179).

function apply<T>(f: ((x: T) => T) | null, x: T): T {
	if (f !== null) { return f(x); }
	return x;
}

console.log(apply<number>((v: number) => v + 1, 10.5).toString());
