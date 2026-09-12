import { createMemo } from "../../src/core/memo";
import { createSignal, Accessor } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";

test "memo without equals propagates every distinct value" {
	const [n, setN] = createSignal(1);
	const m = createMemo(() => n());
	let runs = 0;
	createEffect(() => { m(); runs = runs + 1; });
	assert runs === 1, "ran once on creation";
	setN(2);
	assert runs === 2, "downstream re-ran on change";
}

test "memo with truthiness equals collapses truthy to truthy" {
	const [n, setN] = createSignal(1);
	const cond = createMemo(() => n(), (a, b) => (a !== 0) === (b !== 0));
	let runs = 0;
	createEffect(() => { cond(); runs = runs + 1; });
	assert runs === 1, "ran once on creation";
	setN(2);
	assert runs === 1, "no downstream re-run when truthiness unchanged";
	setN(0);
	assert runs === 2, "re-ran when truthiness flipped to falsy";
}

test "createMemo returns a nominal Accessor" {
	const [n, setN] = createSignal<number>(1);
	const m: Accessor<number> = createMemo(() => n() * 2);
	assert m() === 2;
	setN(3);
	assert m() === 6;
}
