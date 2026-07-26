// Probe: generic f<U>(): U[] instantiated with U = () => number (function type).
// Hypothesis: U[] collapses to U (function) under substitution → "expected Array, got function".

function collect<U>(make: (i: number) => U): U[] {
	const out: U[] = new Array(2);
	out[0] = make(0);
	out[1] = make(1);
	return out;
}

function collect2<U>(make: (i: number) => U): () => U[] {
	let store: U[] = [];
	return () => {
		store = new Array(2);
		store[0] = make(0);
		store[1] = make(1);
		return store;
	};
}

function main(): void {
	const a = collect<() => number>((i) => () => i * 10);
	console.log(a[0]().toString());
	const b = collect2<() => number>((i) => () => i * 100);
	const arr = b();
	console.log(arr[1]().toString());
}
