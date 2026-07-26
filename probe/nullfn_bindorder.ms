// OPEN sibling — unify binding-order divergence (pinned 2026-07-22).
//
// EXPECTED (bug): `msc build` fails ~ "passing 'int' to parameter of incompatible
//   type 'Maybe_fn_fnint32int3215'". T binds to int32 from arg 1 (`10`), overriding
//   the arg-0 arrow's `(v: number)`. Then the (correct) exact-match wrap gate
//   refuses number-arrow → int32-formal → bare msClosure.
// NIM PARITY: sigmatch.nim paramTypesMatchAux binds progressively IN ARG ORDER —
//   arg 0 (the arrow) would bind T=number first. MS lets a later arg win.
// NOT a gap-2 regression: gap-2 (call-site wrap uses substituted formal) is
//   correct; this is a separate unify-order bug. Do NOT "fix" by loosening the
//   wrap gate — that masks the divergence (trace-nim anti-pattern).

function apply<T>(f: ((x: T) => T) | null, x: T): T {
	if (f !== null) { return f(x); }
	return x;
}

console.log(apply((v: number) => v + 1, 10).toString());
