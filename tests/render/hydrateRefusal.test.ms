import { NeonNode, el, text, dynText } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";
import { render, mockHost, mockNode, mockToString, MockNode, Host, HostNode } from "../../src/render/host";
import { hydrate } from "../../src/render/hydrate";
import { createAsyncMemo } from "../../src/render/hydrateMemo";
import { putRecord, putModule, clearRecords } from "../../src/render/hydrationRecords";
import { createComponent } from "../../src/render/component";
import { lazyModule } from "../../src/render/lazy";
import { hydrating } from "../../src/render/claim";
import { Gate, release, opened } from "../core/asyncClock";
import { View, Text } from "../../src/components/primitives";
import { Show, Loading } from "../../src/macros/ui/flow";
import { flush } from "../../src/core/runtime";

function served(tree: NeonNode): MockNode {
	const root = mockNode("root");
	const dispose = render(tree, mockHost(), root as unknown as HostNode, "");
	dispose();
	return root;
}

function refusal(page: NeonNode, root: MockNode): string {
	let said = "";
	try {
		hydrate(page, mockHost(), root as unknown as HostNode);
	} catch (e) { said = e.message; }
	return said;
}

function rebuilt(root: MockNode, page: NeonNode, expected: NeonNode): string {
	const from = root.children[0];
	const dispose = hydrate(page, mockHost(), root as unknown as HostNode);
	const got = mockToString(root);
	dispose();
	if (got !== mockToString(served(expected))) { return "the page holds " + got; }
	if (from.parent !== null) { return "a served node is still in the page"; }
	return "";
}

test "a hydrate refusal inside a reactive region, caught by the caller, leaves the rebuilt page updating" {
	when (debug) {
		const [shown, setShown] = createSignal("one");
		const page = (): NeonNode => <View><Show when={true}><h1>x</h1></Show><Text>{shown()}</Text></View>;
		const root = served(<View><p>x</p><Text>one</Text></View>);
		const said = refusal(page(), root);
		assert said.indexOf("<h1>") >= 0, said;
		root.children = [];
		render(page(), mockHost(), root as unknown as HostNode);
		setShown("two");
		flush();
		assert mockToString(root).indexOf("two") >= 0, mockToString(root);
	}
}

test "a page that differs inside a reactive region is rebuilt in a release build and keeps updating" {
	when (debug) {} else {
		const [shown, setShown] = createSignal("one");
		const page = (): NeonNode => <View><Show when={true}><h1>x</h1></Show><Text>{shown()}</Text></View>;
		const root = served(<View><p>x</p><Text>one</Text></View>);
		const from = root.children[0];
		hydrate(page(), mockHost(), root as unknown as HostNode);
		assert from.parent === null, "the served node left the page";
		setShown("two");
		flush();
		const [two, setTwo] = createSignal("two");
		assert mockToString(root) === mockToString(served(<View><Show when={true}><h1>x</h1></Show><Text>{two()}</Text></View>)), mockToString(root);
	}
}

test "a page missing a node at the top level throws in debug and is rebuilt in release" {
	const page = (): NeonNode => <View><h1>x</h1><Text>one</Text></View>;
	const root = served(<View><p>x</p><Text>one</Text></View>);
	when (debug) {
		const said = refusal(page(), root);
		assert said === "hydrate: the page has no <h1> at child 1 of view", said;
	} else {
		const wrong = rebuilt(root, page(), page());
		assert wrong === "", wrong;
	}
}

test "a page with more children in an element throws in debug and is rebuilt in release" {
	const page = (): NeonNode => <View><Text>one</Text></View>;
	const root = served(<View><Text>one</Text><p>x</p></View>);
	when (debug) {
		const said = refusal(page(), root);
		assert said === "hydrate: the page has more children in view than the tree renders", said;
	} else {
		const wrong = rebuilt(root, page(), page());
		assert wrong === "", wrong;
	}
}

test "a page with more children in a region's element throws in debug and is rebuilt in release" {
	const page = (): NeonNode => <View><Show when={true}><View><Text>a</Text></View></Show></View>;
	const root = served(<View><Show when={true}><View><Text>a</Text><p>x</p></View></Show></View>);
	when (debug) {
		const said = refusal(page(), root);
		assert said === "hydrate: the page has more children in view > view than the tree renders", said;
	} else {
		const wrong = rebuilt(root, page(), page());
		assert wrong === "", wrong;
	}
}

test "a page with more children in the container throws in debug and is rebuilt in release" {
	const page = (): NeonNode => <View><Text>one</Text></View>;
	const root = served(<View><Text>one</Text></View>);
	mockHost().append(root as unknown as HostNode, mockNode("p") as unknown as HostNode);
	when (debug) {
		const said = refusal(page(), root);
		assert said === "hydrate: the page has more children in the container than the tree renders", said;
	} else {
		const wrong = rebuilt(root, page(), page());
		assert wrong === "", wrong;
	}
}

interface Note {
	text: string;
}

async function loadNote(gate: Gate): Promise<Note> {
	await opened(gate);
	return { text: "live" };
}

test "a page with a record that differs throws in debug, and in release is rebuilt from the server's records" {
	clearRecords();
	putRecord("0", JSON.stringify<Note>({ text: "srv" }));
	const root = served(el("p", [], [], dynText((): string => "srv")));
	const gate = new Gate();
	const page = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: Note | null): Promise<Note> => loadNote(gate));
		el("h1", [], [], dynText((): string => data().text))(host, parent, before);
	};
	let got = "";
	when (debug) {
		got = refusal(page, root);
	} else {
		const dispose = hydrate(page, mockHost(), root as unknown as HostNode);
		got = mockToString(root);
		dispose();
	}
	clearRecords();
	await release(gate);
	when (debug) {
		assert got === "hydrate: the page has no <h1> at child 1 of the container", got;
	} else {
		assert got === "<root><h1>srv</h1></root>", got;
	}
}

type Greeting = (props: { label: string }) => NeonNode;

function Hello(props: { label: string }): NeonNode {
	return el("p", [], [], text("hello " + props.label));
}

function Other(props: { label: string }): NeonNode {
	return el("h1", [], [], text("other " + props.label));
}

function lazyShell(Page: Greeting): NeonNode {
	return el("div", [], [], Loading({ children: createComponent(Page, { label: "ssr" }), fallback: el("b", [], [], text("loading")) }));
}

async function loadAfter(gate: Gate, comp: Greeting): Promise<Greeting> {
	await opened(gate);
	return comp;
}

class Calls {
	n: int32 = 0;
}

async function failFirst(gate: Gate, calls: Calls): Promise<Greeting> {
	calls.n += 1;
	await opened(gate);
	if (calls.n === 1) { throw new Error("chunk 404"); }
	return Hello;
}

test "a page with a lazy the client has not loaded claims once the module loads: kept when it matches in debug, rebuilt when it differs in release" {
	const root = served(lazyShell((props: { label: string }): NeonNode => Hello(props)));
	const sent = mockToString(root);
	const top = root.children[0];
	const from = top.children[0];
	const gate = new Gate();
	when (debug) {
		const Page = lazyModule("tests/render/hydrateRefusal/kept", (): Promise<Greeting> => loadAfter(gate, Hello));
		putModule("0", "tests/render/hydrateRefusal/kept");
		const dispose = hydrate(lazyShell(Page), mockHost(), root as unknown as HostNode);
		assert !hydrating() && root.children[0].children[0] === from, "nothing is claimed before the module loads";
		await release(gate);
		assert mockToString(root) === sent && root.children[0].children[0] === from, mockToString(root);
		dispose();
	} else {
		const Page = lazyModule("tests/render/hydrateRefusal/rebuilt", (): Promise<Greeting> => loadAfter(gate, Other));
		putModule("0", "tests/render/hydrateRefusal/rebuilt");
		const dispose = hydrate(lazyShell(Page), mockHost(), root as unknown as HostNode);
		assert !hydrating() && mockToString(root) === sent && root.children[0].children[0] === from, "nothing is claimed before the module loads";
		await release(gate);
		assert mockToString(root) === "<root><div><h1>other ssr</h1></div></root>", mockToString(root);
		assert top.parent === null, "the served node left the page";
		dispose();
	}
	clearRecords();
}

test "a lazy module that fails to load renders the page fresh" {
	const root = served(lazyShell((props: { label: string }): NeonNode => Hello(props)));
	const top = root.children[0];
	const gate = new Gate();
	const calls = new Calls();
	const Page = lazyModule("tests/render/hydrateRefusal/failed", (): Promise<Greeting> => failFirst(gate, calls));
	putModule("0", "tests/render/hydrateRefusal/failed");
	const dispose = hydrate(lazyShell(Page), mockHost(), root as unknown as HostNode);
	await release(gate);
	await release(gate);
	assert calls.n === 2, "the fresh render loads the module again: " + calls.n.toString();
	assert mockToString(root) === "<root><div><p>hello ssr</p></div></root>", mockToString(root);
	assert top.parent === null, "the page was rendered fresh";
	dispose();
	clearRecords();
}
