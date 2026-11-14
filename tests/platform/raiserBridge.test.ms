import {
	render, mockHost, mockNode, mockToString, fireEventWith, fireTouch, MockNode, HostNode,
} from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, Text } from "../../src/components/primitives";
import { Show } from "../../src/macros/ui/flow";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { neonEvent, eventType } from "../../src/render/event";
import { sleepAsync } from "std/core/promise";
import { homeDir } from "std/os";
import {
	GuestProgram, GuestSlot, openGuest, loadGuest, callGuest, hostString, unboxInt,
} from "../../src/platform/raiser/native";
import { Card } from "./raiser/views";

const errors: string[] = [];
let shared: GuestProgram | null = null;
let clock = 1000.0;

function program(): GuestProgram {
	if (shared !== null) { return shared as GuestProgram; }
	const opened = openGuest({ projectRoot: "." });
	if (!opened.ok) { throw new Error(opened.error); }
	const p = opened.value;
	p.onError = (message: string): void => { errors.push(message); };
	const loaded = loadGuest(p, "tests/platform/raiser/app.ms");
	if (!loaded.ok) { throw new Error(loaded.error.map((d) => `${d.file}:${d.line}: ${d.message}`).join("\n")); }
	shared = p;
	return p;
}

function nth(n: MockNode, tag: string, index: int32, found: MockNode[]): MockNode | null {
	if (n.tag === tag) { found.push(n); }
	if (found.length > index) { return found[index]; }
	for (const child of n.children) {
		const hit = nth(child, tag, index, found);
		if (hit !== null) { return hit; }
	}
	return null;
}

function find(n: MockNode, tag: string, index: int32): MockNode {
	const hit = nth(n, tag, index, []);
	if (hit === null) { throw new Error(`no <${tag}> number ${index} in ${mockToString(n)}`); }
	return hit as MockNode;
}

function tap(node: MockNode): void {
	clock += 10;
	fireTouch(node, "onTouchStart", 10, 10, clock);
	flush();
	clock += 10;
	fireTouch(node, "onTouchEnd", 10, 10, clock);
	flush();
	const click = neonEvent(eventType("onPress"));
	click.pointerOrigin = true;
	fireEventWith(node, "onPress", click);
	flush();
}

function cleanups(p: GuestProgram): int32 {
	const got = callGuest(p, "cleanups", []);
	if (!got.ok) { throw new Error(got.error); }
	return unboxInt(got.value.root) as int32;
}

test "a guest mounted through the bridge draws the tree a compiled mount draws" {
	const compiled = mockNode("root");
	const unmountCompiled = render(element(<View><Text>before</Text>{Card("one")}<Text>after</Text></View>), mockHost(), compiled as unknown as HostNode);
	const p = program();
	const bridged = mockNode("root");
	const unmount = render(element(<View>
		<Text>before</Text>
		<GuestSlot program={p} view="card" args={[hostString("one")]} />
		<Text>after</Text>
	</View>), mockHost(), bridged as unknown as HostNode);
	assert errors.length === 0, errors.join("\n");
	assert mockToString(bridged) === mockToString(compiled), `bridged ${mockToString(bridged)} compiled ${mockToString(compiled)}`;
	unmountCompiled();
	unmount();
}

test "a tap on a guest Pressable presses once" {
	const p = program();
	const root = mockNode("root");
	const unmount = render(element(<GuestSlot program={p} view="card" args={[hostString("tap")]} />), mockHost(), root as unknown as HostNode);
	const button = find(root, "pressable", 0);
	tap(button);
	assert mockToString(button).includes("<text>pressed 1</text>"), mockToString(button);
	unmount();
}

test "a guest handler's stopPropagation reaches the native event" {
	const p = program();
	const root = mockNode("root");
	const unmount = render(element(<GuestSlot program={p} view="card" args={[hostString("stop")]} />), mockHost(), root as unknown as HostNode);
	const stopper = find(root, "view", 1);
	const e = neonEvent(eventType("onPointerDown"));
	fireEventWith(stopper, "onPointerDown", e);
	flush();
	assert e.propagationStopped, "the guest stopped the event";
	unmount();
}

test "disposing a slot removes the guest's nodes and keeps the compiled sibling" {
	const p = program();
	const host = mockHost();
	const parent = mockNode("root");
	render(element(<Text>sibling</Text>), host, parent as unknown as HostNode);
	const dispose = render(element(<GuestSlot program={p} view="card" args={[hostString("gone")]} />), host, parent as unknown as HostNode);
	const before = cleanups(p);
	dispose();
	assert mockToString(parent) === "<root><text>sibling</text></root>", mockToString(parent);
	assert cleanups(p) === before + 1, "the guest root was disposed";

	const [shown, setShown] = createSignal(true);
	const outer = mockNode("root");
	const unmountOuter = render(element(<View>
		<Text>sibling</Text>
		<Show when={shown}><GuestSlot program={p} view="card" args={[hostString("shown")]} /></Show>
	</View>), host, outer as unknown as HostNode);
	setShown(false);
	flush();
	assert mockToString(outer) === "<root><view><text>sibling</text></view></root>", mockToString(outer);
	assert errors.length === 0, errors.join("\n");
	unmountOuter();
}

test "two roots in one interpreter keep their own handlers" {
	const p = program();
	const root = mockNode("root");
	const unmount = render(element(<View>
		<GuestSlot program={p} view="card" args={[hostString("a")]} />
		<GuestSlot program={p} view="card" args={[hostString("b")]} />
	</View>), mockHost(), root as unknown as HostNode);
	tap(find(root, "pressable", 0));
	assert mockToString(find(root, "pressable", 0)).includes("<text>pressed 1</text>"), mockToString(root);
	assert mockToString(find(root, "pressable", 1)).includes("<text>pressed 0</text>"), mockToString(root);
	unmount();
}

test "a guest setTimeout fires through the pump with no frame" {
	const p = program();
	const root = mockNode("root");
	const unmount = render(element(<GuestSlot program={p} view="ticker" />), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><text>waiting</text></root>", mockToString(root);
	await sleepAsync(200);
	assert mockToString(root) === "<root><text>fired</text></root>", mockToString(root);
	unmount();
}

test "a failed edit keeps the last good tree, and a new program mounts before the old tree goes" {
	const p = program();
	const root = mockNode("root");
	const unmount = render(element(<GuestSlot program={p} view="card" args={[hostString("edit")]} />), mockHost(), root as unknown as HostNode);
	tap(find(root, "pressable", 0));
	const good = mockToString(root);
	assert good.includes("pressed 1"), good;

	const broken = loadGuest(p, "tests/platform/raiser/broken.ms");
	assert !broken.ok, "the broken edit does not compile";
	assert mockToString(root) === good, mockToString(root);
	tap(find(root, "pressable", 0));
	assert mockToString(root).includes("pressed 2"), "the last good program still runs: " + mockToString(root);

	errors.length = 0;
	const kept = mockToString(root);
	const throwing = loadGuest(p, "tests/platform/raiser/throwing.ms");
	assert throwing.ok, "the throwing edit compiles";
	assert errors.length === 1 && errors[0].includes("this edit fails at mount"), errors.join("\n");
	assert mockToString(root) === kept, mockToString(root);

	errors.length = 0;
	const fixed = loadGuest(p, "tests/platform/raiser/app.ms");
	assert fixed.ok, "the fixed edit compiles";
	assert mockToString(root).includes("pressed 0") && !mockToString(root).includes("pressed 2"), mockToString(root);
	assert errors.length === 0, errors.join("\n");
	unmount();
}

test "openGuest compiles against the runtime root it is given" {
	const installed = openGuest({ projectRoot: ".", runtimeRoot: `${homeDir()}/.metascript` });
	if (!installed.ok) { throw new Error(installed.error); }
	assert loadGuest(installed.value, "tests/platform/raiser/app.ms").ok, "the guest compiles against the installed root";
	const missing = "/nonexistent/raiser-runtime";
	const refused = openGuest({ projectRoot: ".", runtimeRoot: missing });
	assert !refused.ok && refused.error.includes(missing), refused.ok ? "a missing runtime root was accepted" : refused.error;
}
