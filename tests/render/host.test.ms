import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { el, text, dynText } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { direct } from "../../src/macros/ui/direct";
import { HostNode, MockNode, mockNode, mockHost, renderToHost, mockToString } from "../../src/render/host";

test "renderToHost builds tree and binds reactive text (push)" {
	const [name, setName] = createSignal("world");
	const vnode = element(<p>Hi {name()}</p>);
	const root: MockNode = mockNode("root");
	renderToHost(vnode, mockHost(), root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<p>Hi world</p>", "initial host render";
	setName("neon");
	assert mockToString(root.children[0]) === "<p>Hi neon</p>", "host text updated via effect";
}

test "reactive attr: one effect per spot, upsert in place, dispose stops tracking" {
	const [cls, setCls] = createSignal("red");
	const root: MockNode = mockNode("root");
	createRoot((dispose) => {
		renderToHost(element(<p class={cls()}>x</p>), mockHost(), root as unknown as HostNode);
		assert mockToString(root.children[0]) === "<p class=\"red\">x</p>", "initial mount";
		setCls("blue");
		assert mockToString(root.children[0]) === "<p class=\"blue\">x</p>", "attr updated via effect";
		assert root.children[0].attrs.length === 1, "upsert — no duplicate attr entries";
		dispose();
		setCls("green");
		assert mockToString(root.children[0]) === "<p class=\"blue\">x</p>", "no update after dispose";
		return 0;
	});
}

test "null attr: static writes nothing, reactive removes then writes back — tree and direct agree" {
	const s: string | null = null;
	const [t, setT] = createSignal<string | null>("a");
	const host = mockHost();
	const tree: MockNode = mockNode("root");
	const flat: MockNode = mockNode("root");
	createRoot((dispose) => {
		renderToHost(element(<div title={t()} id={s}>x</div>), host, tree as unknown as HostNode);
		const mount = direct(<div title={t()} id={s}>x</div>);
		mount(host, flat as unknown as HostNode, null);
		mount(host, flat as unknown as HostNode, null);
		assert mockToString(tree) === "<root><div title=\"a\">x</div></root>", "tree mount: " + mockToString(tree);
		assert mockToString(flat) === "<root><div title=\"a\">x</div><div title=\"a\">x</div></root>", "direct mount: " + mockToString(flat);
		setT(null);
		assert mockToString(tree) === "<root><div>x</div></root>", "tree null: " + mockToString(tree);
		assert mockToString(flat) === "<root><div>x</div><div>x</div></root>", "direct null: " + mockToString(flat);
		setT("b");
		assert mockToString(tree) === "<root><div title=\"b\">x</div></root>", "tree back: " + mockToString(tree);
		assert mockToString(flat) === "<root><div title=\"b\">x</div><div title=\"b\">x</div></root>", "direct back: " + mockToString(flat);
		dispose();
		return 0;
	});
}

test "null attr at mount: a reactive spot that starts null never shows" {
	const [t, setT] = createSignal<string | null>(null);
	const host = mockHost();
	const tree: MockNode = mockNode("root");
	const flat: MockNode = mockNode("root");
	createRoot((dispose) => {
		renderToHost(element(<div title={t()}>x</div>), host, tree as unknown as HostNode);
		direct(<div title={t()}>x</div>)(host, flat as unknown as HostNode, null);
		assert mockToString(tree) === "<root><div>x</div></root>", "tree: " + mockToString(tree);
		assert mockToString(flat) === "<root><div>x</div></root>", "direct: " + mockToString(flat);
		setT("a");
		assert mockToString(flat) === "<root><div title=\"a\">x</div></root>", "direct write: " + mockToString(flat);
		dispose();
		return 0;
	});
}
