import { NeonNode } from "../../src/render/node";
import { createSignal, Accessor } from "../../src/core/signal";
import { createUniqueId } from "../../src/core/owner";
import { render, hydrate, mockHost, mockNode, mockToString, fireEvent, MockNode, Host, HostNode } from "../../src/render/host";
import { View, Text, Pressable } from "../../src/components/primitives";
import { Portal } from "../../src/render/portal";
import { NeonEvent } from "../../src/render/event";
import { Errored } from "../../src/macros/ui/flow";
import { flush } from "../../src/core/runtime";

function silence(n: MockNode): void {
	n.events = [];
	for (const k of n.children) { silence(k); }
}

// What a browser holds after parsing a served page: the nodes one render left
// behind, with no listener on them and no effect alive.
function served(tree: NeonNode): MockNode {
	const root = mockNode("root");
	const dispose = render(tree, mockHost(), root as unknown as HostNode, "");
	dispose();
	silence(root);
	return root;
}

interface Made {
	elements: number;
	texts: number;
}

function countingHost(made: Made): Host {
	const h = mockHost();
	const element = h.createElement;
	const text = h.createText;
	h.createElement = (tag: string): HostNode => { made.elements += 1; return element(tag); };
	h.createText = (s: string): HostNode => { made.texts += 1; return text(s); };
	return h;
}

function Field(): NeonNode {
	const id = createUniqueId();
	return <input id={id} />;
}

function page(name: Accessor<string>, press: (e: NeonEvent) => void): NeonNode {
	return <View accessibilityLabel="Page">
		<Text>Hi {name()}</Text>
		<Pressable onPress={press}><Text>go</Text></Pressable>
		<p title={name()}>static <b>{name()}</b> tail</p>
		<Field />
	</View>;
}

test "hydrate takes every node from the page and creates none" {
	const [name, _n] = createSignal("Ann");
	const root = served(page(name, (e: NeonEvent): void => {}));
	const before = mockToString(root);
	const view = root.children[0];

	const made: Made = { elements: 0, texts: 0 };
	const [live, _l] = createSignal("Ann");
	hydrate(page(live, (e: NeonEvent): void => {}), countingHost(made), root as unknown as HostNode);
	assert made.elements === 0 && made.texts === 0, "made " + made.elements.toString() + " elements, " + made.texts.toString() + " texts";
	assert mockToString(root) === before, mockToString(root);
	assert root.children.length === 1 && root.children[0] === view, "the page's own node is the live one";
}

test "a signal written after hydrate updates the node the page sent" {
	const [name, _n] = createSignal("Ann");
	const root = served(page(name, (e: NeonEvent): void => {}));
	const bold = root.children[0].children[2].children[1];
	assert mockToString(bold) === "<b>Ann</b>", mockToString(bold);

	const [live, setLive] = createSignal("Ann");
	hydrate(page(live, (e: NeonEvent): void => {}), mockHost(), root as unknown as HostNode);
	setLive("Bob");
	flush();
	assert mockToString(bold) === "<b>Bob</b>", mockToString(bold);
	const [bob, _b] = createSignal("Bob");
	assert mockToString(root) === mockToString(served(page(bob, (e: NeonEvent): void => {}))), mockToString(root);
}

test "an event on a node the page sent reaches the handler" {
	const [name, _n] = createSignal("Ann");
	const root = served(page(name, (e: NeonEvent): void => {}));
	let pressed = 0;
	hydrate(page(name, (e: NeonEvent): void => { pressed += 1; }), mockHost(), root as unknown as HostNode);
	fireEvent(root.children[0].children[1], "onPress");
	flush();
	assert pressed === 1, "pressed " + pressed.toString();
}

function flows(on: Accessor<boolean>, xs: Accessor<number[]>): NeonNode {
	return <View>
		<Show when={on()}><Text>shown</Text></Show>
		<For each={xs()}>{(n: number, i: Accessor<number>): NeonNode => <Text>{n.toString()}</Text>}</For>
		<For each={xs()}>{(n: number, i: Accessor<number>): NeonNode => <Show when={n !== 2}><b>{n.toString()}</b></Show>}</For>
		<Text>end</Text>
	</View>;
}

function flowsAt(on: boolean, xs: number[]): string {
	const [a, _a] = createSignal(on);
	const [b, _b] = createSignal<number[]>(xs);
	return mockToString(served(flows(a, b)));
}

test "Show and For toggle and reorder on the page's nodes after hydrate" {
	const [on, _o] = createSignal(true);
	const [xs, _x] = createSignal<number[]>([1, 2, 3]);
	const root = served(flows(on, xs));
	const before = mockToString(root);

	const made: Made = { elements: 0, texts: 0 };
	const [liveOn, setOn] = createSignal(true);
	const [liveXs, setXs] = createSignal<number[]>([1, 2, 3]);
	hydrate(flows(liveOn, liveXs), countingHost(made), root as unknown as HostNode);
	assert made.elements === 0, "made " + made.elements.toString() + " elements";
	assert mockToString(root) === before, mockToString(root);

	setOn(false);
	flush();
	setXs([3, 1]);
	flush();
	assert mockToString(root) === flowsAt(false, [3, 1]), mockToString(root);
	setOn(true);
	flush();
	setXs([2, 3, 1, 4]);
	flush();
	assert mockToString(root) === flowsAt(true, [2, 3, 1, 4]), mockToString(root);
}

function guarded(on: Accessor<boolean>): NeonNode {
	return <View>
		<Errored fallback={() => <b>sorry</b>}><Text>fine</Text><Show when={on()}><Text>on</Text></Show></Errored>
		<Text>end</Text>
	</View>;
}

test "hydrate takes an Errored's content from the page and creates only the holder it parks content in" {
	const [on, _o] = createSignal(false);
	const root = served(guarded(on));
	const before = mockToString(root);

	const made: Made = { elements: 0, texts: 0 };
	const [liveOn, setOn] = createSignal(false);
	hydrate(guarded(liveOn), countingHost(made), root as unknown as HostNode);
	assert made.elements === 1, "made " + made.elements.toString() + " elements";
	assert mockToString(root) === before, mockToString(root);
	setOn(true);
	flush();
	const [shown, _s] = createSignal(true);
	assert mockToString(root) === mockToString(served(guarded(shown))), mockToString(root);
}

test "regions the page sent empty fill in after hydrate" {
	const [on, _o] = createSignal(false);
	const [xs, _x] = createSignal<number[]>([]);
	const root = served(flows(on, xs));

	const [liveOn, setOn] = createSignal(false);
	const [liveXs, setXs] = createSignal<number[]>([]);
	hydrate(flows(liveOn, liveXs), mockHost(), root as unknown as HostNode);
	setOn(true);
	flush();
	setXs([1, 2]);
	flush();
	assert mockToString(root) === flowsAt(true, [1, 2]), mockToString(root);
}

test "a tree the page was not rendered from fails and names the place in debug, and is rebuilt in release" {
	const root = served(<View><Text>a</Text><p>b</p></View>);
	let said = "";
	try {
		hydrate(<View><Text>a</Text><h1>b</h1></View>, mockHost(), root as unknown as HostNode);
	} catch (e) { said = e.toString(); }
	when (debug) {
		assert said.indexOf("<h1>") >= 0 && said.indexOf("child 2 of view") >= 0, said;
	} else {
		assert said === "" && mockToString(root) === mockToString(served(<View><Text>a</Text><h1>b</h1></View>)), said + mockToString(root);
	}

	const longer = served(<View><Text>a</Text><p>b</p></View>);
	said = "";
	try {
		hydrate(<View><Text>a</Text></View>, mockHost(), longer as unknown as HostNode);
	} catch (e) { said = e.toString(); }
	when (debug) {
		assert said.indexOf("more children") >= 0 && said.indexOf("view") >= 0, said;
	} else {
		assert said === "" && mockToString(longer) === mockToString(served(<View><Text>a</Text></View>)), said + mockToString(longer);
	}
}

test "a failed hydrate leaves the host creating nodes again" {
	const root = served(<View><p>b</p></View>);
	const h = mockHost();
	let failed = false;
	try {
		hydrate(<View><h1>b</h1></View>, h, root as unknown as HostNode);
	} catch (e) { failed = true; }
	when (debug) {
		assert failed, "the mismatch did not fail";
	} else {
		assert !failed && mockToString(root) === "<root><view><h1>b</h1></view></root>", mockToString(root);
	}
	const fresh = mockNode("root");
	render(<View><h1>b</h1></View>, h, fresh as unknown as HostNode);
	assert mockToString(fresh) === "<root><view><h1>b</h1></view></root>", mockToString(fresh);
}

test "children the tree does not own stay where they are" {
	const root = served(<View><canvas></canvas><Text>after</Text></View>);
	const canvas = root.children[0].children[0];
	const foreign = mockNode("foreign");
	canvas.children.push(foreign);
	foreign.parent = canvas;

	let seen: HostNode | null = null;
	hydrate(<View><canvas ref={(n: HostNode): void => { seen = n; }}></canvas><Text>after</Text></View>, mockHost(), root as unknown as HostNode);
	assert seen === (canvas as unknown as HostNode), "the ref received the page's canvas";
	assert canvas.children.length === 1 && canvas.children[0] === foreign, "the foreign child is gone";
}

test "a Portal mounts fresh beside the page's nodes" {
	const tree = (): NeonNode => <View><Portal><Text>over</Text></Portal><Text>under</Text></View>;
	const root = served(tree());
	const before = mockToString(root);
	const h = mockHost();
	hydrate(tree(), h, root as unknown as HostNode);
	assert mockToString(root) === before, mockToString(root);
	const layer = (h.overlayRoot as (n: HostNode) => HostNode)(root as unknown as HostNode) as unknown as MockNode;
	assert mockToString(layer).indexOf("over") >= 0, mockToString(layer);
}

test "a host that cannot take over nodes refuses to hydrate" {
	const root = served(<View></View>);
	const h = mockHost();
	h.claim = null;
	let said = "";
	try {
		hydrate(<View></View>, h, root as unknown as HostNode);
	} catch (e) { said = e.toString(); }
	assert said.indexOf("claim") >= 0, said;
}
