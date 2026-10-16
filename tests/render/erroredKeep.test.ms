// Errored keeps its content: the content is mounted once, a failure parks it behind the fallback
// and a reset brings the same nodes back (Solid: packages/signals/src/boundaries.ts:554 createBoundary's output pass, :464 reset).
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Accessor, createSignal } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
import { Errored } from "../../src/macros/ui/flow";

function throwsWhenOne(a: () => int32, err: Error, runs: int32[]): void {
	createRenderEffect<int32>(
		(p: int32 | null): int32 => { runs[0] = runs[0] + 1; return a(); },
		(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw err; } return null; },
	);
}

function nodeOf(n: HostNode, tag: string): MockNode {
	const m = n as unknown as MockNode;
	for (const c of m.children) {
		if (c.tag === tag) { return c; }
	}
	throw "no <" + tag + "> under " + mockToString(m);
}

const caughtB = (err: Accessor<Error>, reset: () => void): NeonNode => el("b", [], [], text("caught"));

test "the content keeps its state and its nodes through the fallback and a reset" {
	const [a, setA] = createSignal(0);
	const bodyRuns = [0];
	const effectRuns = [0];
	let seven: (() => void) | null = null;
	let again: (() => void) | null = null;
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		bodyRuns[0] = bodyRuns[0] + 1;
		const [count, set] = createSignal(1);
		seven = (): void => { set(7); };
		throwsWhenOne(a, new Error("late"), effectRuns);
		el("p", [], [], dynText((): string => count().toString()))(host, parent, before);
	};
	const host = mockHost();
	const root = host.createElement("root");
	const dispose = render(Errored({
		children: content,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return caughtB(err, reset); },
	}), host, root);
	const shown = (): string => mockToString(root as unknown as MockNode);
	const before = nodeOf(root, "p");
	(seven as () => void)();
	assert shown().includes("<p>7</p>"), shown();

	setA(1);
	assert shown().includes("caught") && !shown().includes("<p>"), "the fallback replaced the content: " + shown();
	setA(0);
	(again as () => void)();
	assert shown().includes("<p>7</p>") && !shown().includes("caught"), "the content came back with its state: " + shown();
	assert nodeOf(root, "p") === before, "the content is the same host node";
	assert bodyRuns[0] === 1, "the view ran once: " + bodyRuns[0].toString();
	dispose();
}

test "reset recomputes only the effect that failed" {
	const [a, setA] = createSignal(0);
	const failing = [0];
	const steady = [0];
	let again: (() => void) | null = null;
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => { steady[0] = steady[0] + 1; return 0; },
			(v: int32, p: int32 | null): Cleanup | null => null,
		);
		throwsWhenOne(a, new Error("late"), failing);
		text("ok")(host, parent, before);
	};
	const host = mockHost();
	const root = host.createElement("root");
	const dispose = render(Errored({
		children: content,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return caughtB(err, reset); },
	}), host, root);
	assert steady[0] === 1 && failing[0] === 1, "each effect ran once at the mount";
	setA(1);
	assert failing[0] === 2, "the failing effect saw the write: " + failing[0].toString();
	setA(0);
	(again as () => void)();
	assert failing[0] === 3, "reset ran the failed effect again: " + failing[0].toString();
	assert steady[0] === 1, "the effect that did not fail was left alone: " + steady[0].toString();
	dispose();
}

test "an error while the content mounts is a tree that never existed: reset mounts fresh content" {
	let attempts = 0;
	let again: (() => void) | null = null;
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		attempts = attempts + 1;
		el("i", [], [], text("partial " + attempts.toString()))(host, parent, before);
		if (attempts < 2) { throw new Error("attempt " + attempts.toString()); }
	};
	const host = mockHost();
	const root = host.createElement("root");
	const dispose = render(Errored({
		children: content,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return caughtB(err, reset); },
	}), host, root);
	const shown = (): string => mockToString(root as unknown as MockNode);
	assert shown().includes("caught") && !shown().includes("partial"), "the partial nodes left the tree: " + shown();
	(again as () => void)();
	assert shown().includes("partial 2") && !shown().includes("partial 1") && !shown().includes("caught"), "reset mounted fresh content: " + shown();
	assert attempts === 2, "the view ran again: " + attempts.toString();
	dispose();
}

test "disposing an Errored with its content parked runs the content cleanups before the release" {
	const [a, setA] = createSignal(0);
	const log: string[] = [];
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		onCleanup(() => { log.push("cleanup"); });
		throwsWhenOne(a, new Error("late"), [0]);
		text("ok")(host, parent, before);
	};
	const host = mockHost();
	const released = host.release;
	host.release = (node: HostNode): void => { log.push("release"); released(node); };
	const root = host.createElement("root");
	const dispose = render(Errored({ children: content, fallback: caughtB }), host, root);
	setA(1);
	assert mockToString(root as unknown as MockNode).includes("caught"), "parked behind the fallback";
	assert log.length === 0, "nothing ran yet: " + log.join(",");
	dispose();
	assert log.join(",") === "cleanup,release", "the content owner is disposed before its nodes are released: " + log.join(",");
}

test "disposing an Errored that shows its content releases only the empty holder" {
	const log: string[] = [];
	const host = mockHost();
	const released = host.release;
	host.release = (node: HostNode): void => { log.push((node as unknown as MockNode).children.length.toString()); released(node); };
	const root = host.createElement("root");
	const dispose = render(Errored({ children: text("ok"), fallback: caughtB }), host, root);
	dispose();
	assert log.join(",") === "0", "one release, of an empty holder: " + log.join(",");
}
