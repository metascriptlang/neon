function run<T>(fn: (d: () => void) => T): T {
	const d = (): void => {};
	return fn(d);
}

function main(): void {
	// A: body with NO return statement at all -> T should be void
	run((d) => {
		const x = 1 + 1;
		console.log(x.toString());
		d();
	});
	console.log("A ok");
}
