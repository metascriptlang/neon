import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, MockNode, HostNode, mockHost, mockNode, render, mockToString } from "../../src/render/host";
import { hydrate } from "../../src/render/hydrate";
import { createComponent } from "../../src/render/component";
import { lazyModule } from "../../src/render/lazy";
import { putModule, clearRecords } from "../../src/render/hydrationRecords";
import { hydrating } from "../../src/render/claim";
import { createSignal } from "../../src/core/signal";
import { flush, getOwner } from "../../src/core/runtime";
import { createMemo } from "../../src/core/memo";
import { Loading } from "../../src/macros/ui/flow";
import { Gate, gated, opened, release } from "../core/asyncClock";

function paragraph(root: MockNode): MockNode {
	for (const n of root.children[0].children) {
		if (n.tag === "p") { return n; }
	}
	throw new Error("the page has no <p>: " + mockToString(root));
}

function Greeting(props: { label: string }): NeonNode {
	return el("p", [], [], text("hello " + props.label));
}

function shell(Page: (props: { label: string }) => NeonNode): NeonNode {
	return el("div", [], [], Loading({ children: createComponent(Page, { label: "ssr" }), fallback: el("b", [], [], text("loading")) }));
}

async function loaded(): Promise<(props: { label: string }) => NeonNode> {
	const gate = new Gate();
	const Page = lazyModule("tests/render/lazyHydrate/page", (): Promise<(props: { label: string }) => NeonNode> => gated(gate, Greeting));
	const scratch = mockNode("root");
	const dispose = render(shell(Page), mockHost(), scratch as unknown as HostNode, "");
	await release(gate);
	dispose();
	return Page;
}

test "a lazy component whose module loaded before hydrate keeps the served node and renders once" {
	const Page = await loaded();
	const root = mockNode("root");
	render(shell(Page), mockHost(), root as unknown as HostNode, "")();
	const sent = mockToString(root);
	const served = paragraph(root);
	assert sent === "<root><div><p>hello ssr</p></div></root>", sent;
	const dispose = hydrate(shell(Page), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === sent, mockToString(root);
	assert paragraph(root) === served, "the page's own <p>";
	dispose();
}

const [greeting, setGreeting] = createSignal("hello");

function LiveGreeting(props: { label: string }): NeonNode {
	return el("p", [], [], dynText((): string => greeting() + " " + props.label));
}

function coldLoader(gate: Gate): () => Promise<(props: { label: string }) => NeonNode> {
	return (): Promise<(props: { label: string }) => NeonNode> => gated(gate, LiveGreeting);
}

async function liveNow(): Promise<(props: { label: string }) => NeonNode> {
	return LiveGreeting;
}

const ServedLive = lazyModule("tests/render/lazyHydrate/served", liveNow);

async function servedPage(): Promise<MockNode> {
	const root = mockNode("root");
	const dispose = render(shell(ServedLive), mockHost(), root as unknown as HostNode, "");
	let polls: int32 = 0;
	while (!mockToString(root).includes("<p>") && polls < 500) { await sleepAsync(1); flush(); polls += 1; }
	dispose();
	return root;
}

test "a served lazy the client has not loaded hydrates after its module loads and keeps the served node" {
	setGreeting("hello");
	const root = await servedPage();
	const sent = mockToString(root);
	const served = paragraph(root);
	assert sent === "<root><div><p>hello ssr</p></div></root>", sent;
	const gate = new Gate();
	const Page = lazyModule("tests/render/lazyHydrate/cold", coldLoader(gate));
	putModule("0", "tests/render/lazyHydrate/cold");
	const dispose = hydrate(shell(Page), mockHost(), root as unknown as HostNode);
	assert !hydrating(), "the claim waits for the module";
	assert mockToString(root) === sent && paragraph(root) === served, mockToString(root);
	await release(gate);
	assert !hydrating(), "the claim ended";
	assert mockToString(root) === sent, mockToString(root);
	assert paragraph(root) === served, "the page's own <p>";
	setGreeting("hi");
	flush();
	assert served.children[0].text === "hi ssr", "the served node is the live one: " + mockToString(root);
	dispose();
	clearRecords();
}

test "a hydrate disposed before its lazy module loads never claims the page" {
	setGreeting("hello");
	const root = await servedPage();
	const sent = mockToString(root);
	const gate = new Gate();
	const Page = lazyModule("tests/render/lazyHydrate/disposed", coldLoader(gate));
	putModule("0", "tests/render/lazyHydrate/disposed");
	const dispose = hydrate(shell(Page), mockHost(), root as unknown as HostNode);
	dispose();
	await release(gate);
	assert !hydrating(), "no claim is left open";
	setGreeting("hi");
	flush();
	assert mockToString(root) === sent, "nothing mounted: " + mockToString(root);
	clearRecords();
}

test "a hydrate disposed before its lazy module loads leaves a later mount into the same container alone" {
	setGreeting("hello");
	const root = await servedPage();
	const gate = new Gate();
	const Page = lazyModule("tests/render/lazyHydrate/remounted", coldLoader(gate));
	putModule("0", "tests/render/lazyHydrate/remounted");
	hydrate(shell(Page), mockHost(), root as unknown as HostNode)();
	clearRecords();
	root.children = [];
	const again = render(shell(Page), mockHost(), root as unknown as HostNode, "");
	const mounted = root.children[0];
	await release(gate);
	setGreeting("hi");
	flush();
	assert root.children.length === 1 && root.children[0] === mounted, "the later mount keeps the container: " + mockToString(root);
	assert mockToString(root) === "<root><div><p>hi ssr</p></div></root>", mockToString(root);
	again();
}

async function failing(gate: Gate): Promise<(props: { label: string }) => NeonNode> {
	await opened(gate);
	throw new Error("chunk 404");
}

test "a hydrate disposed before its lazy module fails to load renders nothing" {
	setGreeting("hello");
	const root = await servedPage();
	const sent = mockToString(root);
	const served = root.children[0];
	const gate = new Gate();
	const Page = lazyModule("tests/render/lazyHydrate/disposedFailed", (): Promise<(props: { label: string }) => NeonNode> => failing(gate));
	putModule("0", "tests/render/lazyHydrate/disposedFailed");
	hydrate(shell(Page), mockHost(), root as unknown as HostNode)();
	await release(gate);
	flush();
	assert mockToString(root) === sent && root.children[0] === served, "no fresh render: " + mockToString(root);
	clearRecords();
}

function idAfter(Page: (props: { label: string }) => NeonNode, ids: string[]): NeonNode {
	const routed: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => {
		Page({ label: "ssr" })(h, p, b);
		createMemo((prev: boolean | null): boolean => {
			const self = getOwner();
			ids.push(self !== null && self.id !== null ? self.id as string : "none");
			return true;
		});
	};
	return el("div", [], [], Loading({ children: routed, fallback: el("b", [], [], text("loading")) }));
}

test "a lazy takes the same hydration ids whether its module is loading or loaded" {
	const gate = new Gate();
	const Page = lazyModule("tests/render/lazyHydrate/ids", coldLoader(gate));
	const ids: string[] = [];
	const first = render(idAfter(Page, ids), mockHost(), mockNode("root") as unknown as HostNode, "");
	await release(gate);
	first();
	render(idAfter(Page, ids), mockHost(), mockNode("root") as unknown as HostNode, "")();
	assert ids.length === 2 && ids[0] === ids[1], "the next memo's id: " + ids.join(" / ");
}
