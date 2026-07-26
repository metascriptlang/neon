function createSignal<T>(v: T): [() => T, (x: T) => void] { return [() => v, (x: T) => {}]; }
interface Cell { setter: ((v: number) => void) | null; }
function f(): () => void {
	const cell: Cell = { setter: null };
	const index = (): void => { if (cell.setter === null) { const [g, s] = createSignal(0); cell.setter = s; } };
	const set = (n: number): void => { if (cell.setter !== null) { cell.setter(n); } };
	index();
	return () => { set(1); };
}
test "m4: minimal — sibling closures, nullable-fn field" { const r = f(); r(); assert true, "ok"; }
