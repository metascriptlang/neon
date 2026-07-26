// OPEN sibling (2026-07-22) — arrow → generic `Maybe<fn>` param NOT closure-lowered.
// Verdict: gap-2 (call-site wrap uses substituted formal) is FIXED and proven by
// neon/tests/core/memo.test.ms (GREEN). But the GENERAL "pass an arrow literal to a
// generic nullable-fn param" still fails: the arrow comes out as `int 0` (unlowered)
// → C "assigning to 'msClosure' from incompatible type 'int'".
//
// Why memo escapes it: memo's `equals` is an OPTIONAL param (`= null`) and T binds
// from `fn: () => T`'s RETURN (arg 0) — a different arg-checking path than a plain
// required generic Maybe<fn> param. This minimal shape has neither, so it hits the
// unlowered-arrow path.
//
// Repro: `msc build probe/nullfn_generic_arg_notlowered.ms` → error at the pick(...) call.
// Family: arrow-arg lowering in generic calls (cousin of R1 "arrow-in-new-arg not lowered").

function pick<T>(seed: T, f: ((a: T, b: T) => boolean) | null): boolean {
	if (f !== null) { return f(seed, seed); }
	return false;
}
console.log(pick(3.5, (a, b) => (a !== 0.0) === (b !== 0.0)).toString());
