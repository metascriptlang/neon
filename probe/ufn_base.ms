function wrapN<U>(x: U): U[] { return [x]; }
function main(): void {
	const a = wrapN<number>(5);          // U = number
	const b = wrapN<string>("hi");       // U = string
	console.log(a[0].toString());
	console.log(b[0]);
}
