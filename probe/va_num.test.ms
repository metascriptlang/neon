test "assert inside a concretely-typed non-void arrow" {
	const f = (v: number): number => {
		assert v > 0, "positive";
		return v * 2;
	};
	assert f(3) === 6, "doubled";
}
