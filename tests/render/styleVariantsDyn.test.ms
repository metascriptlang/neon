// A reactive variant selection (docs/STYLE.md §2, §6): the style expression is
// a CALL, so the call-based rule routes the whole expression through one
// effect (withDynStyleAll → host.setStyle). A static selection pays the same
// single effect that never re-fires — a false positive by design, never a
// frozen snapshot.

import { element } from "../../src/macros/ui/element";
import { NeonNode, withDynStyleAll } from "../../src/render/node";
import { Style, mergeStyle, emptyStyle } from "../../src/render/style";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { renderToHost, mockHost, mockNode, MockNode, HostNode } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";

const s = createStyles({
	btn: {
		padding: 8,
		backgroundColor: "#334",
		variants: {
			state: { on: { backgroundColor: "#445" } },
		},
	},
});

test "a signal-driven selection tracks the signal" {
	const [pressed, setPressed] = createSignal(false);
	const vnode = element(<div style={s.btn({ state: pressed() ? "on" : "" })}></div>);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(vnode, host, root as unknown as HostNode);
	const div = root.children[0];
	const st0 = div.style as Style;
	assert st0.backgroundColor === "#334", "unpressed renders the base";
	assert st0.padding === 8, "base field present";
	setPressed(true);
	const st1 = div.style as Style;
	assert st1.backgroundColor === "#445", "press swaps in the variant";
	setPressed(false);
	const st2 = div.style as Style;
	assert st2.backgroundColor === "#334", "release falls back to the base";
}

test "a static selection still lands on the node" {
	const vnode = element(<div style={s.btn({ state: "on" })}></div>);
	const host = mockHost();
	const root = mockNode("root");
	renderToHost(vnode, host, root as unknown as HostNode);
	const st = root.children[0].style as Style;
	assert st.backgroundColor === "#445", "selected variant applied";
}
