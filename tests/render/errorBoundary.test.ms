import { el, text, NeonNode } from "../../src/render/node";
import { MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Host, HostNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";

function mounted(node: NeonNode): [() => string, () => void] {
	const host = mockHost();
	const root = host.createElement("root");
	const dispose = render(node, host, root);
	return [() => mockToString(root as unknown as MockNode), dispose];
}

test "ErrorBoundary mounts its children when nothing fails" {
	createRoot((d) => {
		const [view, dispose] = mounted(ErrorBoundary({
			children: el("i", [], [], text("ok")),
			fallback: (err: Error, reset: () => void): NeonNode => el("b", [], [], text("caught")),
		}));
		assert view().includes("ok"), "children mounted: " + view();
		assert !view().includes("caught"), "the fallback stayed out: " + view();
		dispose();
		return 0;
	});
}

test "a throw while mounting the children swaps in the fallback" {
	createRoot((d) => {
		const thrown = new Error("mount 7");
		const boom: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			throw thrown;
		};
		let seen: Error | null = null;
		const [view, dispose] = mounted(ErrorBoundary({
			children: boom,
			fallback: (err: Error, reset: () => void): NeonNode => { seen = err; return el("b", [], [], text("caught")); },
		}));
		assert view().includes("caught"), "the fallback is mounted: " + view();
		assert seen === thrown, "the fallback is given the thrown Error itself";
		assert (seen as Error).message === "mount 7", "with its message: [" + (seen as Error).message + "]";
		dispose();
		return 0;
	});
}

test "a throw in a later effect swaps in the fallback" {
	createRoot((d) => {
		const [a, setA] = createSignal(0);
		const thrown = new Error("late 7");
		const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			createEffect(() => { if (a() === 1) { throw thrown; } });
			text("ok")(host, parent, before);
		};
		let seen: Error | null = null;
		const [view, dispose] = mounted(ErrorBoundary({
			children: late,
			fallback: (err: Error, reset: () => void): NeonNode => { seen = err; return el("b", [], [], text("caught")); },
		}));
		assert view().includes("ok"), "children mounted first: " + view();
		setA(1);
		assert seen === thrown, "the boundary caught the later throw and hands it over as is";
		assert (seen as Error).message === "late 7", "with its message: [" + (seen as Error).message + "]";
		assert view().includes("caught") && !view().includes("ok"), "the fallback replaced the children: " + view();
		dispose();
		return 0;
	});
}

test "the failed subtree is torn down before the fallback mounts" {
	createRoot((d) => {
		const [a, setA] = createSignal(0);
		let cleaned = 0;
		const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			onCleanup(() => { cleaned = cleaned + 1; });
			createEffect(() => { if (a() === 1) { throw new Error("late"); } });
			text("ok")(host, parent, before);
		};
		const [view, dispose] = mounted(ErrorBoundary({
			children: late,
			fallback: (err: Error, reset: () => void): NeonNode => el("b", [], [], text("caught")),
		}));
		setA(1);
		assert cleaned > 0, "the children's cleanups ran";
		dispose();
		return 0;
	});
}

test "reset re-mounts the children" {
	createRoot((d) => {
		const [a, setA] = createSignal(0);
		let again: (() => void) | null = null;
		const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			createEffect(() => { if (a() === 1) { throw new Error("late"); } });
			text("ok")(host, parent, before);
		};
		const [view, dispose] = mounted(ErrorBoundary({
			children: late,
			fallback: (err: Error, reset: () => void): NeonNode => { again = reset; return el("b", [], [], text("caught")); },
		}));
		setA(1);
		assert view().includes("caught"), "failed first: " + view();
		setA(0);
		(again as () => void)();
		assert view().includes("ok") && !view().includes("caught"), "reset rebuilt the children: " + view();
		dispose();
		return 0;
	});
}

test "ErrorBoundary works written as a tag" {
	createRoot((d) => {
		const [a, setA] = createSignal(0);
		const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			createEffect(() => { if (a() === 1) { throw new Error("tag 7"); } });
			text("ok")(host, parent, before);
		};
		const fb = (err: Error, reset: () => void): NeonNode => element(<b>{"caught " + err.message}</b>);
		const [view, dispose] = mounted(element(<div><ErrorBoundary fallback={fb}>{late}</ErrorBoundary></div>));
		assert view().includes("ok"), "children mounted through the tag: " + view();
		setA(1);
		assert view().includes("caught tag 7"), "the tag renders the message, not a JSON dump: " + view();
		dispose();
		return 0;
	});
}

test "the fallback keeps the Error in a signal and reads it back" {
	createRoot((d) => {
		const [last, setLast] = createSignal<Error | null>(null);
		const thrown = new Error("x7");
		const boom: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			throw thrown;
		};
		const [view, dispose] = mounted(ErrorBoundary({
			children: boom,
			fallback: (err: Error, reset: () => void): NeonNode => {
				setLast(err);
				return el("b", [], [], text("caught " + (last() as Error).message));
			},
		}));
		assert view().includes("caught x7"), "the fallback read the Error back from its signal: " + view();
		assert last() === thrown, "the signal still holds the same Error after the mount";
		dispose();
		return 0;
	});
}

test "a sibling of the boundary keeps running after the boundary fails" {
	createRoot((d) => {
		const [a, setA] = createSignal(0);
		const [b, setB] = createSignal(0);
		let seen = 0;
		const late: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			createEffect(() => { if (a() === 1) { throw new Error("late"); } });
		};
		const [view, dispose] = mounted(el("div", [], [], ErrorBoundary({
			children: late,
			fallback: (err: Error, reset: () => void): NeonNode => el("b", [], [], text("caught")),
		})));
		createEffect(() => { b(); seen = seen + 1; });
		setA(1);
		const before = seen;
		setB(1);
		assert seen > before, "the scheduler still drains after a caught error";
		dispose();
		return 0;
	});
}
