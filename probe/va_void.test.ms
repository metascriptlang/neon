test "assert inside a concretely-typed void arrow" {
	const f = (v: number): void => {
		assert v > 0, "positive";
	};
	f(3);
}
