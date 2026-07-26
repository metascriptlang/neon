function run<T>(fn: (d: () => void) => T): T {
	const d = (): void => {};
	return fn(d);
}

test "assert inside a generic void callback" {
	run((d) => {
		const x = 1 + 1;
		assert x === 2, "x is 2";
		d();
	});
}
