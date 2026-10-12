import { createSignal } from "../../src/core/signal";
import { createEffect, createBindingEffect } from "../../src/core/effect";
import { createMemo } from "../../src/core/memo";
import { createRoot, createUniqueId } from "../../src/core/owner";
import { getOwner } from "../../src/core/runtime";
import { Computation } from "../../src/core/types";

function ownerId(): string {
	const id = (getOwner() as Computation).id;
	return id === null ? "none" : "[" + (id as string) + "]";
}

test "an owner outside an id-carrying root has no id" {
	let seen: string[] = [];
	createRoot((dispose) => {
		seen.push(ownerId());
		createEffect(() => { seen.push(ownerId()); });
		dispose();
	});
	assert seen.join(" ") === "none none", seen.join(" ");
}

test "children of an id-carrying root count up from it, nested ones from their parent" {
	let seen: string[] = [];
	createRoot((dispose) => {
		seen.push(ownerId());
		createEffect(() => {
			seen.push(ownerId());
			createEffect(() => { seen.push(ownerId()); });
			createEffect(() => { seen.push(ownerId()); });
		});
		createEffect(() => { seen.push(ownerId()); });
		const double = createMemo<number>(() => { seen.push(ownerId()); return 2; });
		double();
		dispose();
	}, "");
	assert seen.join(" ") === "[] [0] [00] [01] [1] [2]", seen.join(" ");
}

test "a child index past one base-36 digit carries its length" {
	let last = "";
	createRoot((dispose) => {
		for (let i = 0; i < 37; i += 1) { createEffect(() => { last = ownerId(); }); }
		dispose();
	}, "r");
	assert last === "[rA10]", last;
}

test "a binding effect shares its owner's id and counter" {
	let seen: string[] = [];
	createRoot((dispose) => {
		createBindingEffect(() => {
			seen.push(ownerId());
			createEffect(() => { seen.push(ownerId()); });
		});
		createEffect(() => { seen.push(ownerId()); });
		dispose();
	}, "");
	assert seen.join(" ") === "[] [0] [1]", seen.join(" ");
}

test "a root under an id-carrying owner takes the next child id" {
	let seen: string[] = [];
	createRoot((dispose) => {
		createRoot((inner) => { seen.push(ownerId()); inner(); });
		createRoot((inner) => { seen.push(ownerId()); inner(); });
		dispose();
	}, "");
	assert seen.join(" ") === "[0] [1]", seen.join(" ");
}

test "a re-run hands its children the same ids again" {
	const [count, setCount] = createSignal(0);
	let seen: string[] = [];
	createRoot((dispose) => {
		createEffect(() => {
			count();
			createEffect(() => { seen.push(ownerId()); });
			seen.push(createUniqueId());
		});
		setCount(1);
		dispose();
	}, "");
	assert seen.join(" ") === "[00] 01 [00] 01", seen.join(" ");
}

test "createUniqueId is the same in two renders of one tree and counts alone outside one" {
	const tree = (): string => {
		let ids: string[] = [];
		createRoot((dispose) => {
			ids.push(createUniqueId());
			createEffect(() => { ids.push(createUniqueId()); });
			ids.push(createUniqueId());
			dispose();
		}, "");
		return ids.join(" ");
	};
	const first = tree();
	assert first === "0 10 2", first;
	assert tree() === first, "a second render of the tree drew different ids";

	const a = createUniqueId();
	let b = "";
	createRoot((dispose) => { b = createUniqueId(); dispose(); });
	assert a !== b && a.startsWith("cl-") && b.startsWith("cl-"), a + " " + b;
}
