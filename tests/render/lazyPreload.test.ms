import { el, text, NeonNode } from "../../src/render/node";
import { MockNode, HostNode, mockHost, mockNode, render, hydrate, mockToString } from "../../src/render/host";
import { lazyModule, preloadServedLazy, preloadLazy, createComponent } from "../../src/render/component";
import { putModule, clearRecords } from "../../src/render/hydrationRecords";
import { Loading } from "../../src/macros/ui/flow";
import { Gate, gated, release } from "../core/asyncClock";

function Greeting(props: { label: string }): NeonNode {
	return el("p", [], [], text("hello " + props.label));
}

function shell(Page: (props: { label: string }) => NeonNode): NeonNode {
	return el("div", [], [], Loading({ children: createComponent(Page, { label: "ssr" }), fallback: el("b", [], [], text("loading")) }));
}

function loaderOf(gate: Gate): () => Promise<(props: { label: string }) => NeonNode> {
	return (): Promise<(props: { label: string }) => NeonNode> => gated(gate, Greeting);
}

async function served(key: string): Promise<MockNode> {
	const gate = new Gate();
	const Page = lazyModule(key, loaderOf(gate));
	const scratch = mockNode("root");
	const dispose = render(shell(Page), mockHost(), scratch as unknown as HostNode, "");
	await release(gate);
	dispose();
	const root = mockNode("root");
	render(shell(Page), mockHost(), root as unknown as HostNode, "")();
	return root;
}

test "hydrating a lazy whose module the client has not loaded keeps the served node once the preload has run" {
	const root = await served("tests/render/lazyPreload/served");
	const sent = mockToString(root);
	const first = root.children[0].children[0];
	assert sent === "<root><div><p>hello ssr</p></div></root>", sent;
	const gate = new Gate();
	const Client = lazyModule("tests/render/lazyPreload/client", loaderOf(gate));
	putModule("0", "tests/render/lazyPreload/client");
	const ready = preloadServedLazy();
	await release(gate);
	await ready;
	const dispose = hydrate(shell(Client), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === sent, mockToString(root);
	assert root.children[0].children[0] === first, "the page's own <p>";
	dispose();
	clearRecords();
}

test "a key the page lists and the client never registered is an error naming the key" {
	let message = "";
	try {
		await preloadLazy(["tests/render/lazyPreload/absent"]);
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.includes("[LAZY_UNREGISTERED]") && message.includes("tests/render/lazyPreload/absent"), message;
}

test "one key under two different loads is an error, and the same load registers once" {
	const load = loaderOf(new Gate());
	lazyModule("tests/render/lazyPreload/dup", load);
	lazyModule("tests/render/lazyPreload/dup", load);
	let message = "";
	try {
		lazyModule("tests/render/lazyPreload/dup", loaderOf(new Gate()));
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.includes("[LAZY_DUPLICATE_KEY]"), message;
}
