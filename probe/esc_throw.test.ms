test "A: uncaught throw escapes the test fn" {
	const g = (v: number): number => {
		if (v > 0) { throw new Error("boom"); }
		return v;
	};
	const r = g(1);
	assert r === 999, "never reached";
}
test "B: a later test still runs correctly" {
	assert 1 + 1 === 2, "arith";
}
