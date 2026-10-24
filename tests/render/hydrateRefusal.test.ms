import { NeonNode, el, dynText } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";
import { render, hydrate, mockHost, mockNode, mockToString, MockNode, Host, HostNode } from "../../src/render/host";
import { createAsyncMemo } from "../../src/render/hydrateMemo";
import { putRecord, clearRecords } from "../../src/render/hydrationRecords";
import { Gate, release, opened } from "../core/asyncClock";
import { View, Text } from "../../src/components/primitives";
import { Show } from "../../src/macros/ui/flow";
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
