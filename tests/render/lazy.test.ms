// lazy builds on the async memo as Solid's lazy does (packages/solid/src/client/component.ts:127): one shared load, a memo per instance, the Loading fallback while it is pending.
import { el, text, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { lazyModule, createComponent } from "../../src/render/component";
import { lazy } from "../../src/macros/lazy";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { sleepAsync as pause } from "std/core/promise";
import { Loading, For } from "../../src/macros/ui/flow";
import { Gate, gated, release } from "../core/asyncClock";

const waiting: NeonNode = el("b", [], [], text("loading"));
const gate = new Gate();
const loads = [0];

function Greeting(props: { label: string }): NeonNode {
	return el("p", [], [], text("hello " + props.label));
}

async function loadGreeting(): Promise<(props: { label: string }) => NeonNode> {
	loads[0] = loads[0] + 1;
	return gated(gate, Greeting);
}

const Lazy = lazyModule("tests/render/lazy/greeting", loadGreeting);

test "a lazy component shows the Loading fallback until its load settles, and loads once for two instances" {
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: createComponent(Lazy, { label: "one" }), fallback: waiting })(h, parent, before);
		Loading({ children: createComponent(Lazy, { label: "two" }), fallback: waiting })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown().includes("<b>loading</b>") && !shown().includes("<p>"), "fallback first: " + shown();
	await release(gate);
	assert shown().includes("<p>hello one</p>") && shown().includes("<p>hello two</p>") && !shown().includes("loading"), "both after the load: " + shown();
	assert loads[0] === 1, "one load for both: " + loads[0].toString();
	dispose();
}

test "a lazy component whose module has loaded mounts at once with no fallback" {
	const host = mockHost();
	const root = host.createElement("root");
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: createComponent(Lazy, { label: "late" }), fallback: waiting })(h, parent, before);
	};
	const dispose = render(app, host, root);
	const out = mockToString(root as unknown as MockNode);
	assert out.includes("<p>hello late</p>") && !out.includes("loading"), out;
	assert loads[0] === 1, "no second load: " + loads[0].toString();
	dispose();
}

test "a lazy component inside a For row under Loading mounts when its module settles" {
	const late = lazyModule("tests/render/lazy/greeting", loadGreeting);
	const [items, _set] = createSignal<int32[]>([1]);
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = Loading({ children: <For each={items}>{(i: int32): NeonNode => createComponent(late, { label: "row" })}</For>, fallback: waiting });
	const dispose = render(app, host, root);
	let polls: int32 = 0;
	while (shown().includes("loading") && polls < 200) { await pause(1); flush(); polls += 1; }
	assert shown().includes("<p>hello row</p>") && !shown().includes("loading"), "row after the load: " + shown();
	dispose();
}

// Parked on ~/metascript/.inbox/compiler/2026-10-24-msc-test-of-a-dynamic-import-aborts-on-c-with-no-module-record.md: the real import runs on C too once msc test keeps its module record.
when (js) {
	import { sleepAsync } from "std/core/promise";

	async function loadPage(): Promise<(props: { label: string }) => NeonNode> {
		const m = await import("./lazy/page");
		return m.Page;
	}

	const Page = lazy(loadPage);

	test "a lazy component over a dynamic import shows the fallback and then the page" {
		const host = mockHost();
		const root = host.createElement("root");
		const shown = (): string => mockToString(root as unknown as MockNode);
		const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
			Loading({ children: createComponent(Page, { label: "one" }), fallback: waiting })(h, parent, before);
		};
		const dispose = render(app, host, root);
		assert shown().includes("<b>loading</b>") && !shown().includes("<p>"), "fallback first: " + shown();
		let polls: int32 = 0;
		while (shown().includes("loading") && polls < 500) { await sleepAsync(1); polls += 1; }
		assert shown().includes("<p>page one</p>") && !shown().includes("loading"), "page after the import: " + shown();
		dispose();
	}
}
