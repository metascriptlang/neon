import { el, text, NeonNode } from "../../src/render/node";
import { MockNode, HostNode, mockHost, mockNode, render, hydrate, mockToString } from "../../src/render/host";
import { lazy, createComponent } from "../../src/render/component";
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
	const Page = lazy((): Promise<(props: { label: string }) => NeonNode> => gated(gate, Greeting));
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
