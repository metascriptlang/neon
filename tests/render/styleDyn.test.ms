// Reactive style fields (docs/STYLE.md §6, S4a): a style field whose expression
// is reactive becomes ONE effect updating exactly that property through
// host.setStyleProp; the remaining fields stay static on VNode.style. No
// whole-style re-apply, no re-render — the Solid model, per-property.

import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { Style } from "../../src/render/style";
import { renderToHost, mockHost, mockNode, MockNode, HostNode } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";

test "a dynamic style field tracks its signal" {
	const [w, setW] = createSignal(20);
	const vnode = element(<div style={{ width: w(), backgroundColor: "red" }}></div>);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(vnode, host, root as unknown as HostNode);
	const div = root.children[0];
	const st0 = div.style as Style;
	assert st0.width === 20, "initial signal value applied";
	assert st0.backgroundColor === "red", "static field applied alongside";
	setW(35);
	const st1 = div.style as Style;
	assert st1.width === 35, "signal change lands on the property";
	assert st1.backgroundColor === "red", "static field untouched by the update";
}

test "a derived style expression is reactive too" {
	const [n, setN] = createSignal(1);
	const vnode = element(<div style={{ height: n() * 10 }}></div>);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(vnode, host, root as unknown as HostNode);
	const div = root.children[0];
	assert (div.style as Style).height === 10, "derived initial value";
	setN(4);
	assert (div.style as Style).height === 40, "derived update";
}

test "an all-static style object still lands as one constant" {
	const vnode = element(<div style={{ width: 200, height: 120 }}></div>);
	assert vnode.dynStyle === null, "no dynamic entries for a static object";
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(vnode, host, root as unknown as HostNode);
	const st = root.children[0].style as Style;
	assert st.width === 200, "static width";
	assert st.height === 120, "static height";
}

test "an identical signal value is not re-written to the host" {
	const [w, setW] = createSignal(20);
	const vnode = element(<div style={{ width: w() }}></div>);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(vnode, host, root as unknown as HostNode);
	const div = root.children[0];
	const before = div.style;
	setW(20);
	assert div.style === before, "same value writes nothing";
	assert (div.style as Style).width === 20, "value intact";
}
