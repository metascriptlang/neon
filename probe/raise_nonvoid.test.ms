function f(v: number): number {
	if (v < 0) { throw new Error("neg"); }
	return v * 2;
}
test "raise from a non-void fn, nested in a non-void arrow" {
	const g = (v: number): number => {
		if (v < 0) { throw new Error("neg2"); }
		return f(v);
	};
	assert g(3) === 6, "ok";
}
