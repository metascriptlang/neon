function createSignal<T>(v: T): [() => T, (x: T) => void] { return [() => v, (x: T) => {}]; }
interface Cell { getter: (() => number) | null; setter: ((v: number) => void) | null; }
function f(): () => void {
	const cell: Cell = { getter: null, setter: null };
	const index = (): number => {
		if (cell.getter === null) { const [g, s] = createSignal(0); cell.getter = g; cell.setter = s; }
		return (cell.getter as () => number)();
	};
	const set = (n: number): void => { if (cell.setter !== null) { cell.setter(n); } };
	index();
	return () => { set(1); };
}
test "m3: lazy-signal like mrepro" { const r = f(); r(); assert true, "ok"; }
