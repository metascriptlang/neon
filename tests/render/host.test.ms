import { createSignal, Accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { createEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { NeonNode, el, text, dynText } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { flush } from "../../src/core/runtime";

test "render builds tree and binds reactive text (push)" {
	const [name, setName] = createSignal("world");
	const vnode = element(<p>Hi {name()}</p>);
	const root: MockNode = mockNode("root");
	render(vnode, mockHost(), root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<p>Hi world</p>", "initial host render";
	setName("neon");
	flush();
	assert mockToString(root.children[0]) === "<p>Hi neon</p>", "host text updated via effect";
}

let probeCleanups = 0;
let probeEffectRuns = 0;

interface ProbeProps {
	label: Accessor<string>;
}

function Probe(props: ProbeProps): NeonNode {
	createEffect<string>(
		(p: string | null): string => props.label(),
		(label: string, p: string | null): Cleanup | null => { probeEffectRuns = probeEffectRuns + 1; return null; },
	);
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
	flush();
	assert mockToString(root) === "<root><p>b</p></root>", "live before dispose: " + mockToString(root);
	assert probeEffectRuns === 2, "effect reran once: " + probeEffectRuns.toString();
	assert probeCleanups === 0, "no cleanup while mounted";
	dispose();
	assert probeCleanups === 1, "cleanup ran once: " + probeCleanups.toString();
	setLabel("c");
	flush();
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
	flush();
	assert mockToString(root.children[0]) === "<p class=\"blue\">x</p>", "attr updated via effect";
	assert root.children[0].attrs.length === 1, "upsert — no duplicate attr entries";
	dispose();
	setCls("green");
	flush();
	assert mockToString(root.children[0]) === "<p class=\"blue\">x</p>", "no update after dispose";
}

test "null attr: static writes nothing, reactive removes then writes back on every mounted instance" {
	const s: string | null = null;
	const [t, setT] = createSignal<string | null>("a");
	const host = mockHost();
	const root: MockNode = mockNode("root");
	const mount = element(<div title={t()} id={s}>x</div>);
	const first = render(mount, host, root as unknown as HostNode);
	const second = render(mount, host, root as unknown as HostNode);
	assert mockToString(root) === "<root><div title=\"a\">x</div><div title=\"a\">x</div></root>", "mount: " + mockToString(root);
	setT(null);
	flush();
	assert mockToString(root) === "<root><div>x</div><div>x</div></root>", "null: " + mockToString(root);
	setT("b");
	flush();
	assert mockToString(root) === "<root><div title=\"b\">x</div><div title=\"b\">x</div></root>", "back: " + mockToString(root);
	first();
	second();
}

test "null attr at mount: a reactive spot that starts null never shows" {
	const [t, setT] = createSignal<string | null>(null);
	const host = mockHost();
	const root: MockNode = mockNode("root");
	const dispose = render(element(<div title={t()}>x</div>), host, root as unknown as HostNode);
	assert mockToString(root) === "<root><div>x</div></root>", "mount: " + mockToString(root);
	setT("a");
	flush();
	assert mockToString(root) === "<root><div title=\"a\">x</div></root>", "write: " + mockToString(root);
	dispose();
}

// web/src/client.ts:426: render drains once, so the mount is on the host when it returns; a later write waits for the drain
test "render has mounted when it returns and a later write lands on flush()" {
	const [name, setName] = createSignal("world");
	const root: MockNode = mockNode("root");
	render(element(<p>Hi {name()}</p>), mockHost(), root as unknown as HostNode);
	assert mockToString(root.children[0]) === "<p>Hi world</p>", "mounted";
	setName("neon");
	assert mockToString(root.children[0]) === "<p>Hi world</p>", "the host waits for the drain";
	flush();
	assert mockToString(root.children[0]) === "<p>Hi neon</p>", "drained";
}
