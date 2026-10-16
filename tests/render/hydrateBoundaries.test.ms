import { NeonNode, el, text } from "../../src/render/node";
import { render, hydrate, mockHost, mockNode, mockToString, MockNode, Host, HostNode } from "../../src/render/host";
import { Loading } from "../../src/macros/ui/flow";
import { createAsyncMemo } from "../../src/core/memo";
import { resetErrorHalt } from "../../src/core/runtime";
import { Gate, gated, release } from "../core/asyncClock";
import { loadingIdsApp, loadingIdsClient } from "../browser/boundaryPages";

function silence(n: MockNode): void {
	n.events = [];
	for (const k of n.children) { silence(k); }
}

function served(tree: NeonNode): MockNode {
	const root = mockNode("root");
	const dispose = render(tree, mockHost(), root as unknown as HostNode, "");
	dispose();
	silence(root);
	return root;
}

interface Made {
	elements: number;
}

function countingHost(made: Made): Host {
	const h = mockHost();
	const element = h.createElement;
	h.createElement = (tag: string): HostNode => { made.elements += 1; return element(tag); };
	return h;
}

function childAt(root: MockNode, path: int32[]): MockNode {
	let at = root;
	for (const i of path) { at = at.children[i]; }
	return at;
}

const waiting: NeonNode = el("b", [], [], text("wait"));

function staticLoading(): NeonNode {
	return el("div", [], [], Loading({ children: el("p", [], [], text("hi")), fallback: waiting }));
}

test "a served Loading with static content claims its nodes and creates only the boundary's holder" {
	resetErrorHalt();
	const root = served(staticLoading());
	const page = childAt(root, [0, 0]);
	const before = mockToString(root);
	const made: Made = { elements: 0 };
	const dispose = hydrate(staticLoading(), countingHost(made), root as unknown as HostNode);
	assert made.elements === 1, "made " + made.elements.toString() + " elements, the holder is the one allowed";
	assert mockToString(root) === before, mockToString(root);
	assert childAt(root, [0, 0]) === page, "the content is the page's own <p>";
	dispose();
}

function pendingPage(good: Gate): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(good, 8));
		el("div", [], [], Loading({
			fallback: waiting,
			children: (h: Host, p: HostNode, b: HostNode | null): void => {
				const n = data();
				el("p", [], [], text("n" + n.toString()))(h, p, b);
			},
		}))(host, parent, before);
	};
}

test "a served Loading whose read is still pending on the client claims the served fallback and mounts the content when it lands" {
	resetErrorHalt();
	const good = new Gate();
	const root = served(pendingPage(good));
	assert mockToString(root) === "<root><div><b>wait</b></div></root>", "the page shows the fallback: " + mockToString(root);
	const fallbackNode = childAt(root, [0, 0]);
	const made: Made = { elements: 0 };
	const dispose = hydrate(pendingPage(good), countingHost(made), root as unknown as HostNode);
	assert made.elements === 1, "made " + made.elements.toString() + " elements, the holder is the one allowed";
	assert mockToString(root) === "<root><div><b>wait</b></div></root>", mockToString(root);
	assert childAt(root, [0, 0]) === fallbackNode, "the fallback is the page's own <b>";
	await release(good);
	assert made.elements === 2, "the content mounted fresh when it landed: " + made.elements.toString();
	assert mockToString(root) === "<root><div><p>n8</p></div></root>", "landed: " + mockToString(root);
	dispose();
}

test "a Loading on the client draws the owner ids the server draws for the same tree" {
	const loading = mockNode("div");
	const disposeLoading = render(loadingIdsApp(), mockHost(), loading as unknown as HostNode, "");
	assert mockToString(loading) === loadingIdsClient, mockToString(loading);
	disposeLoading();
}
