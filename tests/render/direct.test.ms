// Direct emission V1 — differential against tree emission on the mock host:
// same JSX through both emissions must be byte-identical, before and after
// signal updates (tree emission is the oracle — docs/RENDER-MODEL.md).

import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { element } from "../../src/macros/ui/element";
import { direct } from "../../src/macros/ui/direct";
import { NeonNode } from "../../src/render/node";
import { renderToHost, mockHost, mockNode, mockToString, fireEvent, MockNode, Host, HostNode } from "../../src/render/host";

test "static + dynamic text + event: direct matches tree" {
	const [name, setName] = createSignal("an");
	let clicks = 0;
	const inc = () => { clicks = clicks + 1; };
	const host = mockHost();

	const treeRoot = mockNode("root");
	const view: NeonNode = element(<div class="box"><p>hello {name()}</p><button onClick={inc}>+</button></div>);
	renderToHost(view, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div class="box"><p>hello {name()}</p><button onClick={inc}>+</button></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setName("binh");
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);

	const btn = (directRoot as MockNode).children[0].children[1];
	fireEvent(btn, "onClick");
	assert clicks === 1, "clicks=" + clicks.toString();
}

test "deep nesting: direct matches tree" {
	const [v, setV] = createSignal("x");
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<ul><li><span>a</span></li><li>{v()}</li></ul>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<ul><li><span>a</span></li><li>{v()}</li></ul>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: " + mockToString(directRoot);
	setV("y");
	assert mockToString(treeRoot) === mockToString(directRoot), "after set: " + mockToString(directRoot);
}

test "multiple attrs and multiple dynamic spots keep distinct temps" {
	const [a, setA] = createSignal("1");
	const [b, setB] = createSignal("2");
	const host = mockHost();

	const treeRoot = mockNode("root");
	const tv: NeonNode = element(<div id="x" class="y"><p>{a()}</p><p>{b()}</p><span>{a()}</span></div>);
	renderToHost(tv, host, treeRoot as unknown as HostNode);

	const directRoot = mockNode("root");
	const mount = direct(<div id="x" class="y"><p>{a()}</p><p>{b()}</p><span>{a()}</span></div>);
	const dnode = mount(host);
	host.append(directRoot as unknown as HostNode, dnode);

	assert mockToString(treeRoot) === mockToString(directRoot), "initial: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setA("7");
	assert mockToString(treeRoot) === mockToString(directRoot), "after setA: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	setB("9");
	assert mockToString(treeRoot) === mockToString(directRoot), "after setB: tree=" + mockToString(treeRoot) + " direct=" + mockToString(directRoot);
	assert mockToString(directRoot).includes("7") && mockToString(directRoot).includes("9"), "both updated: " + mockToString(directRoot);
}
