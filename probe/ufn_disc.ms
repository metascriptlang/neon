// array literal (no new Array), isolate pure U[] substitution
function wrapFn<U>(x: U): U[] { return [x]; }

function main(): void {
	// U = function
	const a = wrapFn<() => number>(() => 5);
	console.log(a[0]().toString());
}
