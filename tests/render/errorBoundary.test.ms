import { el, text, NeonNode } from "../../src/render/node";
import { MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Host, HostNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { Accessor, createSignal } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
import { Errored } from "../../src/macros/ui/flow";

function throwsWhenOne(a: () => int32, err: Error): void {
	createRenderEffect<int32>(
		(p: int32 | null): int32 => a(),
		(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw err; } return null; },
	);
}

function throwsInCompute(a: () => int32, err: Error): void {
	createRenderEffect<int32>(
		(p: int32 | null): int32 => { if (a() === 1) { throw err; } return 0; },
		(v: int32, p: int32 | null): Cleanup | null => null,
	);
}

function mounted(node: NeonNode): [() => string, () => void] {
	const host = mockHost();
	const root = host.createElement("root");
	const dispose = render(node, host, root);
	return [() => mockToString(root as unknown as MockNode), dispose];
}

// client/flow.ts:424 Errored over boundaries.ts:770 createErrorBoundary

test "Errored mounts its children when nothing fails" {
	const [view, dispose] = mounted(Errored({
		children: el("i", [], [], text("ok")),
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("b", [], [], text("caught")),
	}));
	assert view().includes("ok"), "children mounted: " + view();
	assert !view().includes("caught"), "the fallback stayed out: " + view();
	dispose();
}

test "a throw while mounting the children swaps in the fallback" {
	const thrown = new Error("mount 7");
	const boom: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		throw thrown;
	};
	let seen: Error | null = null;
	const [view, dispose] = mounted(Errored({
		children: boom,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { seen = err(); return el("b", [], [], text("caught")); },
	}));
	assert view().includes("caught"), "the fallback is mounted: " + view();
	assert seen === thrown, "the fallback is given the thrown Error itself";
	assert (seen as Error).message === "mount 7", "with its message: [" + (seen as Error).message + "]";
	dispose();
}

test "a throw in a later effect swaps in the fallback" {
	const [a, setA] = createSignal(0);
	const thrown = new Error("late 7");
	const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		throwsWhenOne(a, thrown);
		text("ok")(host, parent, before);
	};
	let seen: Error | null = null;
	const [view, dispose] = mounted(Errored({
		children: late,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { seen = err(); return el("b", [], [], text("caught")); },
	}));
	assert view().includes("ok"), "children mounted first: " + view();
	setA(1);
	assert seen === thrown, "the boundary caught the later throw and hands it over as is";
	assert view().includes("caught") && !view().includes("ok"), "the fallback replaced the children: " + view();
	dispose();
}

test "the failed subtree is torn down when the fallback shows" {
	const [a, setA] = createSignal(0);
	let cleaned = 0;
	const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		onCleanup(() => { cleaned = cleaned + 1; });
		throwsInCompute(a, new Error("late"));
		text("ok")(host, parent, before);
	};
	const [view, dispose] = mounted(Errored({
		children: late,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("b", [], [], text("caught")),
	}));
	setA(1);
	assert cleaned > 0, "the children's cleanups ran";
	dispose();
}

test "reset re-mounts the children" {
	const [a, setA] = createSignal(0);
	let again: (() => void) | null = null;
	let mounts = 0;
	const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		mounts = mounts + 1;
		throwsWhenOne(a, new Error("late"));
		text("ok")(host, parent, before);
	};
	const [view, dispose] = mounted(Errored({
		children: late,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return el("b", [], [], text("caught")); },
	}));
	setA(1);
	assert view().includes("caught"), "failed first: " + view();
	setA(0);
	(again as () => void)();
	assert view().includes("ok") && !view().includes("caught"), "reset rebuilt the children: " + view();
	assert mounts === 2, "the children were built again, not kept: " + mounts.toString();
	dispose();
}

test "reset after a mount throw tries the children again, and fails again if they still throw" {
	let attempts = 0;
	let again: (() => void) | null = null;
	const boom: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		attempts = attempts + 1;
		if (attempts < 3) { throw new Error("attempt " + attempts.toString()); }
		text("ok")(host, parent, before);
	};
	const [view, dispose] = mounted(Errored({
		children: boom,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return el("b", [], [], text("caught " + err().message)); },
	}));
	assert view().includes("caught attempt 1"), "first failure: " + view();
	(again as () => void)();
	assert view().includes("caught attempt 2"), "the retry failed again and shows its own error: " + view();
	(again as () => void)();
	assert view().includes("ok") && !view().includes("caught"), "the third try mounted: " + view();
	dispose();
}

test "Errored works written as a tag" {
	const [a, setA] = createSignal(0);
	const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		throwsWhenOne(a, new Error("tag 7"));
		text("ok")(host, parent, before);
	};
	const [view, dispose] = mounted(element(<div><Errored fallback={(err, reset) => <b>{"caught " + err().message}</b>}>{late}</Errored></div>));
	assert view().includes("ok"), "children mounted through the tag: " + view();
	setA(1);
	assert view().includes("caught tag 7"), "the tag renders the message: " + view();
	dispose();
}

test "a fallback that ignores the error is a function of no parameters" {
	const boom: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		throw new Error("x");
	};
	const [view, dispose] = mounted(element(<div><Errored fallback={() => <b>sorry</b>}>{boom}</Errored></div>));
	assert view().includes("sorry"), "the zero-parameter fallback shows: " + view();
	dispose();
}

// boundaries.ts:554 the fallback runs outside its own boundary
test "an error inside the fallback goes to the outer Errored" {
	const boom: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		text("x")(host, parent, before);
		throw new Error("inner");
	};
	const badFallback = (err: Accessor<Error>, reset: () => void): NeonNode => (host: Host, parent: HostNode, before: HostNode | null): void => {
		text("y")(host, parent, before);
		throw new Error("fallback of " + err().message);
	};
	const [view, dispose] = mounted(Errored({
		children: Errored({ children: boom, fallback: badFallback }),
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("b", [], [], text("outer " + err().message)),
	}));
	assert view().includes("outer fallback of inner"), "the outer boundary caught the fallback's throw: " + view();
	dispose();
}

// createErrorBoundary.test.ts:107 the nearest boundary of the kind takes the error
test "nested Errored: the nearest one catches" {
	const [a, setA] = createSignal(0);
	const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		throwsWhenOne(a, new Error("deep"));
		text("ok")(host, parent, before);
	};
	const [view, dispose] = mounted(Errored({
		children: el("p", [], [], Errored({
			children: late,
			fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("b", [], [], text("inner " + err().message)),
		})),
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("b", [], [], text("outer")),
	}));
	setA(1);
	assert view().includes("inner deep") && !view().includes("outer"), "only the inner fallback shows: " + view();
	dispose();
}

test "a sibling of the boundary keeps running after the boundary fails" {
	const [a, setA] = createSignal(0);
	const [b, setB] = createSignal(0);
	let seen = 0;
	const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		throwsInCompute(a, new Error("late"));
	};
	const [view, dispose] = mounted(el("div", [], [], Errored({
		children: late,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => el("b", [], [], text("caught")),
	})));
	createRenderEffect<int32>(
		(p: int32 | null): int32 => b(),
		(v: int32, p: int32 | null): Cleanup | null => { seen = seen + 1; return null; },
	);
	setA(1);
	const before = seen;
	setB(1);
	assert seen > before, "the scheduler still drains after a caught error";
	dispose();
}
