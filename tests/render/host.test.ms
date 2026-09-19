import { createSignal, Accessor } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { onCleanup } from "../../src/core/cleanup";
import { createEffect } from "../../src/core/effect";
import { NeonNode, el, text, dynText } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";

test "render builds tree and binds reactive text (push)" {
	const [name, setName] = createSignal("world");
	const vnode = element(<p>Hi {name()}</p>);
	const root: MockNode = mockNode("root");
	render(vnode, mockHost(), root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<p>Hi world</p>", "initial host render";
	setName("neon");
	assert mockToString(root.children[0]) === "<p>Hi neon</p>", "host text updated via effect";
}

let probeCleanups = 0;
let probeEffectRuns = 0;

interface ProbeProps {
	label: Accessor<string>;
}

function Probe(props: ProbeProps): NeonNode {
	createEffect(() => { props.label(); probeEffectRuns = probeEffectRuns + 1; });
	onCleanup(() => { probeCleanups = probeCleanups + 1; });
	return element(<p>{props.label()}</p>);
}

test "render owns the mount: its dispose runs cleanups once and stops every write" {
	const [label, setLabel] = createSignal("a");
	const root: MockNode = mockNode("root");
	probeCleanups = 0;
	probeEffectRuns = 0;
	const dispose = render(element(<Probe label={label()} />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><p>a</p></root>", "mounted: " + mockToString(root);
	setLabel("b");
	assert mockToString(root) === "<root><p>b</p></root>", "live before dispose: " + mockToString(root);
	assert probeEffectRuns === 2, "effect reran once: " + probeEffectRuns.toString();
	assert probeCleanups === 0, "no cleanup while mounted";
	dispose();
	assert probeCleanups === 1, "cleanup ran once: " + probeCleanups.toString();
	setLabel("c");
	assert mockToString(root) === "<root><p>b</p></root>", "no host write after dispose: " + mockToString(root);
	assert probeEffectRuns === 2, "effect stopped: " + probeEffectRuns.toString();
	dispose();
	assert probeCleanups === 1, "second dispose is a no-op: " + probeCleanups.toString();
}

test "reactive attr: one effect per spot, upsert in place, dispose stops tracking" {
	const [cls, setCls] = createSignal("red");
	const root: MockNode = mockNode("root");
	const dispose = render(element(<p class={cls()}>x</p>), mockHost(), root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<p class=\"red\">x</p>", "initial mount";
	setCls("blue");
	assert mockToString(root.children[0]) === "<p class=\"blue\">x</p>", "attr updated via effect";
	assert root.children[0].attrs.length === 1, "upsert — no duplicate attr entries";
	dispose();
	setCls("green");
	assert mockToString(root.children[0]) === "<p class=\"blue\">x</p>", "no update after dispose";
}

test "null attr: static writes nothing, reactive removes then writes back on every mounted instance" {
	const s: string | null = null;
	const [t, setT] = createSignal<string | null>("a");
	const host = mockHost();
	const root: MockNode = mockNode("root");
	createRoot((dispose) => {
		const mount = element(<div title={t()} id={s}>x</div>);
		mount(host, root as unknown as HostNode, null);
		mount(host, root as unknown as HostNode, null);
		assert mockToString(root) === "<root><div title=\"a\">x</div><div title=\"a\">x</div></root>", "mount: " + mockToString(root);
		setT(null);
		assert mockToString(root) === "<root><div>x</div><div>x</div></root>", "null: " + mockToString(root);
		setT("b");
		assert mockToString(root) === "<root><div title=\"b\">x</div><div title=\"b\">x</div></root>", "back: " + mockToString(root);
		dispose();
		return 0;
	});
}

test "null attr at mount: a reactive spot that starts null never shows" {
	const [t, setT] = createSignal<string | null>(null);
	const host = mockHost();
	const root: MockNode = mockNode("root");
	createRoot((dispose) => {
		render(element(<div title={t()}>x</div>), host, root as unknown as HostNode);
		assert mockToString(root) === "<root><div>x</div></root>", "mount: " + mockToString(root);
		setT("a");
		assert mockToString(root) === "<root><div title=\"a\">x</div></root>", "write: " + mockToString(root);
		dispose();
		return 0;
	});
}
