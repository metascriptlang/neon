// ref — the escape hatch to the host node. The callback fires once per mount
// with the node the element became, identically on both emissions.

import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { direct } from "../../src/macros/ui/direct";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, renderToHost, mockToString } from "../../src/render/host";
import { View, TextInput } from "../../src/starter/rn";

test "ref hands the completed host node to the callback — tree emission" {
	let seen = "";
	const grab: (n: HostNode) => void = (n) => { seen = mockToString(n as unknown as MockNode); };
	const root: MockNode = mockNode("root");
	const view: NeonNode = element(<div class="box"><p ref={grab}>hi</p></div>);
	renderToHost(view, mockHost(), root as unknown as HostNode);
	assert seen === "<p>hi</p>", "ref saw the finished node, seen=" + seen;
	assert mockToString(root) === "<root><div class=\"box\"><p>hi</p></div></root>", "ref leaves no attribute behind: " + mockToString(root);
}

test "ref fires the same way on direct emission" {
	let seen = "";
	const grab: (n: HostNode) => void = (n) => { seen = mockToString(n as unknown as MockNode); };
	const host = mockHost();
	const root: MockNode = mockNode("root");
	const mount = direct(<div class="box"><p ref={grab}>hi</p></div>);
	host.append(root as unknown as HostNode, mount(host));
	assert seen === "<p>hi</p>", "ref saw the finished node, seen=" + seen;
	assert mockToString(root) === "<root><div class=\"box\"><p>hi</p></div></root>", "ref leaves no attribute behind: " + mockToString(root);
}

test "ref on the root element of a site" {
	let treeTag = "";
	let directTag = "";
	const grabTree: (n: HostNode) => void = (n) => { treeTag = (n as unknown as MockNode).tag; };
	const grabDirect: (n: HostNode) => void = (n) => { directTag = (n as unknown as MockNode).tag; };
	const host = mockHost();

	const treeRoot: MockNode = mockNode("root");
	renderToHost(element(<section ref={grabTree}>x</section>), host, treeRoot as unknown as HostNode);

	const directRoot: MockNode = mockNode("root");
	const mount = direct(<section ref={grabDirect}>x</section>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert treeTag === "section", "tree ref, tag=" + treeTag;
	assert directTag === "section", "direct ref, tag=" + directTag;
	assert mockToString(treeRoot) === mockToString(directRoot), "emissions agree: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
}

test "ref reaches the universal vocabulary, not just raw tags" {
	let viewTag = "";
	let inputTag = "";
	const grabView: (n: HostNode) => void = (n) => { viewTag = (n as unknown as MockNode).tag; };
	const grabInput: (n: HostNode) => void = (n) => { inputTag = (n as unknown as MockNode).tag; };
	const root: MockNode = mockNode("root");
	renderToHost(element(<View ref={grabView}><TextInput ref={grabInput} /></View>), mockHost(), root as unknown as HostNode);
	assert viewTag === "view", "View ref, tag=" + viewTag;
	assert inputTag === "textinput", "TextInput ref, tag=" + inputTag;
}

test "ref fires after a reactive child is bound, on both emissions" {
	const [n, _setN] = createSignal("7");
	let treeSeen = "";
	let directSeen = "";
	const grabTree: (h: HostNode) => void = (h) => { treeSeen = mockToString(h as unknown as MockNode); };
	const grabDirect: (h: HostNode) => void = (h) => { directSeen = mockToString(h as unknown as MockNode); };
	const host = mockHost();

	const treeRoot: MockNode = mockNode("root");
	renderToHost(element(<p ref={grabTree}>{n()}</p>), host, treeRoot as unknown as HostNode);

	const directRoot: MockNode = mockNode("root");
	const mount = direct(<p ref={grabDirect}>{n()}</p>);
	host.append(directRoot as unknown as HostNode, mount(host));

	assert treeSeen === "<p>7</p>", "tree ref saw the bound child, seen=" + treeSeen;
	assert directSeen === "<p>7</p>", "direct ref saw the bound child, seen=" + directSeen;
}

test "an inline arrow ref crosses raw" {
	let seen = "";
	const root: MockNode = mockNode("root");
	renderToHost(element(<p ref={(n: HostNode) => { seen = (n as unknown as MockNode).tag; }}>hi</p>), mockHost(), root as unknown as HostNode);
	assert seen === "p", "inline arrow ref fired, seen=" + seen;
}
