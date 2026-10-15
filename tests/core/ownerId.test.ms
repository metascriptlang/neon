import { createSignal } from "../../src/core/signal";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { createMemo } from "../../src/core/memo";
import { createRoot, createUniqueId } from "../../src/core/owner";
import { getOwner, flush, setServerDepth } from "../../src/core/runtime";
import { Computation, Cleanup } from "../../src/core/types";

function renderEffect(compute: () => void): void {
	createRenderEffect<boolean>(
		(p: boolean | null): boolean => { compute(); return true; },
		(v: boolean, p: boolean | null): Cleanup | null => null,
	);
}

function ownerId(): string {
	const id = (getOwner() as Computation).id;
	return id === null ? "none" : "[" + (id as string) + "]";
}

test "an owner outside an id-carrying root has no id" {
	let seen: string[] = [];
	createRoot((dispose) => {
		seen.push(ownerId());
		renderEffect(() => { seen.push(ownerId()); });
		dispose();
	});
	assert seen.join(" ") === "none none", seen.join(" ");
}

test "children of an id-carrying root count up from it, nested ones from their parent" {
	let seen: string[] = [];
	createRoot((dispose) => {
		seen.push(ownerId());
		renderEffect(() => {
			seen.push(ownerId());
			renderEffect(() => { seen.push(ownerId()); });
			renderEffect(() => { seen.push(ownerId()); });
		});
		renderEffect(() => { seen.push(ownerId()); });
		const double = createMemo<number>(() => { seen.push(ownerId()); return 2; });
		double();
		dispose();
	}, "");
	assert seen.join(" ") === "[] [0] [00] [01] [1] [2]", seen.join(" ");
}

test "a child index past one base-36 digit carries its length" {
	let last = "";
	createRoot((dispose) => {
		for (let i = 0; i < 37; i += 1) { renderEffect(() => { last = ownerId(); }); }
		dispose();
	}, "r");
	assert last === "[rA10]", last;
}

test "a transparent render effect shares its owner's id and counter" {
	let seen: string[] = [];
	createRoot((dispose) => {
		createRenderEffect<boolean>(
			(p: boolean | null): boolean => {
				seen.push(ownerId());
				renderEffect(() => { seen.push(ownerId()); });
				return true;
			},
			(v: boolean, p: boolean | null): Cleanup | null => null,
			{ transparent: true },
		);
		renderEffect(() => { seen.push(ownerId()); });
		dispose();
	}, "");
	assert seen.join(" ") === "[] [0] [1]", seen.join(" ");
}

test "a transparent user effect shares its owner's id and counter" {
	let seen: string[] = [];
	createRoot((dispose) => {
		createEffect<boolean>(
			(p: boolean | null): boolean => {
				seen.push(ownerId());
				renderEffect(() => { seen.push(ownerId()); });
				return true;
			},
			(v: boolean, p: boolean | null): Cleanup | null => null,
			{ transparent: true },
		);
		renderEffect(() => { seen.push(ownerId()); });
		dispose();
	}, "");
	assert seen.join(" ") === "[] [0] [1]", seen.join(" ");
}

test "a plain render effect takes a child id of its own" {
	let seen: string[] = [];
	createRoot((dispose) => {
		renderEffect(() => {
			seen.push(ownerId());
			renderEffect(() => { seen.push(ownerId()); });
		});
		renderEffect(() => { seen.push(ownerId()); });
		dispose();
	}, "");
	assert seen.join(" ") === "[0] [00] [1]", seen.join(" ");
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
	let stop: (() => void) | null = null;
	createRoot((dispose) => {
		stop = dispose;
		renderEffect(() => {
			count();
			renderEffect(() => { seen.push(ownerId()); });
			seen.push(createUniqueId());
		});
	}, "");
	setCount(1);
	flush();
	(stop as () => void)();
	assert seen.join(" ") === "[00] 01 [00] 01", seen.join(" ");
}

test "createUniqueId is the same in two renders of one tree and counts alone outside one" {
	const tree = (): string => {
		let ids: string[] = [];
		createRoot((dispose) => {
			ids.push(createUniqueId());
			renderEffect(() => { ids.push(createUniqueId()); });
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

function effectTree(): string {
	const ids: string[] = [];
	createRoot((dispose) => {
		createEffect<boolean>(
			(p: boolean | null): boolean => { ids.push(ownerId()); return true; },
			(v: boolean, p: boolean | null): Cleanup | null => null,
		);
		renderEffect(() => { ids.push(ownerId()); });
		ids.push(createUniqueId());
		dispose();
	}, "");
	return ids.join(" ");
}

test "an effect takes the same child ids on the server as on the client" {
	const client = effectTree();
	setServerDepth(1);
	let server = "";
	try {
		server = effectTree();
	} finally {
		setServerDepth(0);
	}
	assert client === "[0] [1] 2", client;
	assert server === client, "server " + server + " client " + client;
}

test "on the server a render effect applies once and a user effect never does" {
	let user = 0;
	let render = 0;
	setServerDepth(1);
	try {
		createRoot((dispose) => {
			createEffect<boolean>(
				(p: boolean | null): boolean => true,
				(v: boolean, p: boolean | null): Cleanup | null => { user += 1; return null; },
			);
			createRenderEffect<boolean>(
				(p: boolean | null): boolean => true,
				(v: boolean, p: boolean | null): Cleanup | null => { render += 1; return null; },
			);
			dispose();
		}, "");
	} finally {
		setServerDepth(0);
	}
	assert user === 0 && render === 1, "user " + user.toString() + " render " + render.toString();
}
