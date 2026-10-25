import { el, text, dynText, NeonNode } from "../../src/render/node";
import { MockNode, HostNode, mockHost, mockNode, render, hydrate, mockToString } from "../../src/render/host";
import { lazyModule, createComponent } from "../../src/render/component";
import { putModule, clearRecords } from "../../src/render/hydrationRecords";
import { hydrating } from "../../src/render/claim";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { Loading } from "../../src/macros/ui/flow";
import { Gate, gated, release } from "../core/asyncClock";

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
	const served = root.children[0].children[0];
	assert sent === "<root><div><p>hello ssr</p></div></root>", sent;
	const dispose = hydrate(shell(Page), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === sent, mockToString(root);
	assert root.children[0].children[0] === served, "the page's own <p>";
	dispose();
}

const [greeting, setGreeting] = createSignal("hello");

function LiveGreeting(props: { label: string }): NeonNode {
	return el("p", [], [], dynText((): string => greeting() + " " + props.label));
}

function coldLoader(gate: Gate): () => Promise<(props: { label: string }) => NeonNode> {
	return (): Promise<(props: { label: string }) => NeonNode> => gated(gate, LiveGreeting);
}

function servedPage(): MockNode {
	const root = mockNode("root");
	render(shell((props: { label: string }): NeonNode => LiveGreeting(props)), mockHost(), root as unknown as HostNode, "")();
	return root;
}

test "a served lazy the client has not loaded hydrates after its module loads and keeps the served node" {
	setGreeting("hello");
	const root = servedPage();
	const sent = mockToString(root);
	const served = root.children[0].children[0];
	assert sent === "<root><div><p>hello ssr</p></div></root>", sent;
	const gate = new Gate();
	const Page = lazyModule("tests/render/lazyHydrate/cold", coldLoader(gate));
	putModule("0", "tests/render/lazyHydrate/cold");
	const dispose = hydrate(shell(Page), mockHost(), root as unknown as HostNode);
	assert !hydrating(), "the claim waits for the module";
	assert mockToString(root) === sent && root.children[0].children[0] === served, mockToString(root);
	await release(gate);
	assert !hydrating(), "the claim ended";
	assert mockToString(root) === sent, mockToString(root);
	assert root.children[0].children[0] === served, "the page's own <p>";
	setGreeting("hi");
	flush();
	assert served.children[0].text === "hi ssr", "the served node is the live one: " + mockToString(root);
	dispose();
	clearRecords();
}

test "a hydrate disposed before its lazy module loads never claims the page" {
	setGreeting("hello");
	const root = servedPage();
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
