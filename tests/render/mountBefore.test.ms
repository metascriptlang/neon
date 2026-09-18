import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { mapArray } from "../../src/core/array";
import { element } from "../../src/macros/ui/element";
import { NeonNode, el, text, regionNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockNode, mockHost, mountInto, viewOf, mockToString } from "../../src/render/host";
import { Row, makeRow } from "../../src/render/reconcile";
import { createContext, useContext } from "../../src/render/context";

interface Theme { accent: string; }

function twoSiblings(host: Host): MockNode {
	const root = mockNode("root");
	host.append(root as unknown as HostNode, host.createElement("a"));
	host.append(root as unknown as HostNode, host.createElement("z"));
	return root;
}

function tailOf(root: MockNode): HostNode {
	return root.children[root.children.length - 1] as unknown as HostNode;
}

function Boxed(props: { tag: string }): NeonNode {
	return element(<p class={props.tag}>c</p>);
}

test "an element mounts in front of an existing sibling" {
	const host = mockHost();
	const root = twoSiblings(host);
	mountInto(element(<p>x</p>), host, root as unknown as HostNode, tailOf(root));
	assert mockToString(root) === "<root><a></a><p>x</p><z></z></root>", "got " + mockToString(root);
}

test "a fragment mounts every root in front of the sibling, in order" {
	const host = mockHost();
	const root = twoSiblings(host);
	mountInto(element(<><p>1</p><p>2</p></>), host, root as unknown as HostNode, tailOf(root));
	assert mockToString(root) === "<root><a></a><p>1</p><p>2</p><z></z></root>", "got " + mockToString(root);
}

test "a component unwraps and mounts in front of the sibling" {
	const host = mockHost();
	const root = twoSiblings(host);
	mountInto(element(<Boxed tag="p" />), host, root as unknown as HostNode, tailOf(root));
	assert mockToString(root) === "<root><a></a><p class=\"p\">c</p><z></z></root>", "got " + mockToString(root);
}

test "a provider scope carries the insertion point into its child" {
	const T = createContext<Theme>({ accent: "red" });
	const host = mockHost();
	const root = twoSiblings(host);
	const app: NeonNode = element(
		<T.Provider value={{ accent: "blue" }}>
			<div>{useContext(T).accent}</div>
		</T.Provider>
	);
	mountInto(app, host, root as unknown as HostNode, tailOf(root));
	assert mockToString(root) === "<root><a></a><div>blue</div><z></z></root>", "got " + mockToString(root);
}

test "a region anchors in front of the sibling and grows on its own side" {
	createRoot((dispose) => {
		const host = mockHost();
		const root = twoSiblings(host);
		const [list, setList] = createSignal<number[]>([1, 2]);
		const region = regionNode((h) => {
			return mapArray<number, Row>(() => list(), (v, i) => makeRow(viewOf(el("li", [], [], [text("" + v)]))));
		});
		mountInto(region, host, root as unknown as HostNode, tailOf(root));
		assert mockToString(root) === "<root><a></a><li>1</li><li>2</li><z></z></root>", "initial: " + mockToString(root);
		setList([1, 2, 3]);
		assert mockToString(root) === "<root><a></a><li>1</li><li>2</li><li>3</li><z></z></root>", "append stays on the region side: " + mockToString(root);
		setList([3]);
		assert mockToString(root) === "<root><a></a><li>3</li><z></z></root>", "shrink leaves the siblings alone: " + mockToString(root);
		dispose();
		return 0;
	});
}

test "a null insertion point still appends at the end" {
	const host = mockHost();
	const root = twoSiblings(host);
	mountInto(element(<p>x</p>), host, root as unknown as HostNode, null);
	assert mockToString(root) === "<root><a></a><z></z><p>x</p></root>", "got " + mockToString(root);
}
