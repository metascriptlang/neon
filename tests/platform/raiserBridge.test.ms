import {
	render, mockHost, mockNode, mockToString, fireEventWith, fireTouch, MockNode, HostNode,
} from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, Text, Pressable } from "../../src/components/primitives";
import { Show } from "../../src/macros/ui/flow";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { neonEvent, eventType, NeonEvent } from "../../src/render/event";
import { Host } from "../../src/render/hostTypes";
import { sleepAsync } from "std/core/promise";
import { homeDir } from "std/os";
import {
	GuestProgram, GuestSlot, SlotHandle, SlotOutcome, SlotShown, SlotRoot,
	openGuest, loadGuest, callGuest, openSlot, closeSlot, slotStatus,
	hostString, hostValue, boxBool, boxInt, unboxInt, RaiserHostValue,
} from "../../src/platform/raiser/native";
import { Card } from "./raiser/views";

const errors: string[] = [];
let shared: GuestProgram | null = null;
let running = "";
let clock = 1000.0;

function load(p: GuestProgram, path: string): boolean {
	const loaded = loadGuest(p, `tests/platform/raiser/${path}`);
	if (loaded.ok) { running = path; }
	return loaded.ok;
}

function program(): GuestProgram {
	if (shared !== null && running === "app.ms") { return shared as GuestProgram; }
	if (shared === null) {
		const opened = openGuest({ projectRoot: "." });
		if (!opened.ok) { throw new Error(opened.error); }
		shared = opened.value;
		(shared as GuestProgram).onError = (message: string): void => { errors.push(message); };
	}
	const p = shared as GuestProgram;
	const loaded = loadGuest(p, "tests/platform/raiser/app.ms");
	if (!loaded.ok) { throw new Error(loaded.error.map((d) => `${d.file}:${d.line}: ${d.message}`).join("\n")); }
	running = "app.ms";
	errors.length = 0;
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

function identity(slot: SlotHandle): string {
	const root = slotStatus(slot).root;
	return root === null ? "none" : `${(root as SlotRoot).key}/${(root as SlotRoot).generation}`;
}

function shown(slot: SlotHandle): string {
	const status = slotStatus(slot);
	return `outcome ${status.outcome as int32} shown ${status.shown as int32} root ${identity(slot)}`;
}

function cleanups(p: GuestProgram): int32 {
	const got = callGuest(p, "cleanups", []);
	if (!got.ok) { throw new Error(got.error); }
	return unboxInt(got.value.root) as int32;
}

function opened(): GuestProgram {
	const made = openGuest({ projectRoot: "." });
	if (!made.ok) { throw new Error(made.error); }
	const p = made.value;
	p.onError = (message: string): void => { errors.push(message); };
	return p;
}

function loaded(p: GuestProgram, path: string): GuestProgram {
	const got = loadGuest(p, `tests/platform/raiser/${path}`);
	if (!got.ok) { throw new Error(got.error.map((d) => `${d.file}:${d.line}: ${d.message}`).join("\n")); }
	return p;
}

let editorShared: GuestProgram | null = null;

function editorProgram(): GuestProgram {
	if (editorShared === null) { editorShared = loaded(opened(), "editor.ms"); }
	return editorShared as GuestProgram;
}

class Embedder {
	log: string[] = [];
	slot: SlotHandle | null = null;
	place: MockNode | null = null;
}

function embed(editor: GuestProgram, app: GuestProgram): Embedder {
	const seen = new Embedder();
	editor.onPlace = (name: string, host: Host, node: HostNode): void => {
		seen.log.push(`place ${name}`);
		seen.place = node as unknown as MockNode;
		seen.slot = openSlot(app, "card", [hostString("app")], host, node, null);
	};
	editor.onPlaceGone = (name: string): void => {
		const place = seen.place as MockNode;
		const held = mockToString(place).includes("<text>app</text>") ? "holding the app" : "empty";
		const where = place.parent !== null && !place.freed ? "attached" : "detached";
		closeSlot(seen.slot as SlotHandle);
		seen.log.push(`gone ${name} ${where} ${held}, then ${place.children.length} children`);
	};
	return seen;
}

const GONE = "gone preview attached holding the app, then 0 children";

function inside(n: MockNode, root: MockNode): boolean {
	let at = n.parent;
	while (at !== null) {
		if (at === root) { return true; }
		at = (at as MockNode).parent;
	}
	return false;
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

	assert !load(p, "broken.ms"), "the broken edit does not compile";
	assert mockToString(root) === good, mockToString(root);
	tap(find(root, "pressable", 0));
	assert mockToString(root).includes("pressed 2"), "the last good program still runs: " + mockToString(root);

	errors.length = 0;
	const kept = mockToString(root);
	assert load(p, "throwing.ms"), "the throwing edit compiles";
	assert errors.length === 1 && errors[0].includes("this edit fails at mount"), errors.join("\n");
	assert mockToString(root) === kept, mockToString(root);

	errors.length = 0;
	tap(find(root, "pressable", 0));
	assert errors.length > 0 && errors.every((e) => e.includes("refused onTouchStart") || e.includes("refused onTouchEnd") || e.includes("refused onPress")), "the inert tree refuses its events: " + errors.join("\n");
	assert mockToString(root) === kept, mockToString(root);

	errors.length = 0;
	assert load(p, "app.ms"), "the fixed edit compiles";
	assert mockToString(root).includes("pressed 0") && !mockToString(root).includes("pressed 2"), mockToString(root);
	assert errors.length === 0, errors.join("\n");
	unmount();
}

test "openSlot mounts a guest outside any reactive owner, and closeSlot removes it and disposes its root" {
	const p = program();
	const host = mockHost();
	const parent = mockNode("root");
	const before = cleanups(p);
	const slot = openSlot(p, "card", [hostString("open")], host, parent as unknown as HostNode, null);
	assert mockToString(parent).includes("<text>open</text>"), mockToString(parent);
	closeSlot(slot);
	assert parent.children.length === 0, mockToString(parent);
	assert cleanups(p) === before + 1, "the guest root was disposed";
	assert errors.length === 0, errors.join("\n");
}

test "a second closeSlot is refused by name" {
	const p = program();
	const slot = openSlot(p, "card", [hostString("twice")], mockHost(), mockNode("root") as unknown as HostNode, null);
	closeSlot(slot);
	let refused = "none";
	try { closeSlot(slot); } catch (e) { refused = (e as Error).message; }
	assert refused.includes("card") && refused.includes("already closed"), refused;
}

test "openGuest compiles against the runtime root it is given" {
	const installed = openGuest({ projectRoot: ".", runtimeRoot: `${homeDir()}/.metascript` });
	if (!installed.ok) { throw new Error(installed.error); }
	assert loadGuest(installed.value, "tests/platform/raiser/app.ms").ok, "the guest compiles against the installed root";
	const missing = "/nonexistent/raiser-runtime";
	const refused = openGuest({ projectRoot: ".", runtimeRoot: missing });
	assert !refused.ok && refused.error.includes(missing), refused.ok ? "a missing runtime root was accepted" : refused.error;
}

test "a slot reports each load's outcome and binds its root's identity to one mount" {
	const p = program();
	const host = mockHost();
	const parent = mockNode("root");
	const slot = openSlot(p, "card", [hostString("status")], host, parent as unknown as HostNode, null);
	const first = slotStatus(slot);
	assert first.outcome === SlotOutcome.Mounted && first.shown === SlotShown.Guest && first.root !== null, shown(slot);
	const mounted = identity(slot);

	assert !load(p, "broken.ms"), "the broken edit does not compile";
	assert slotStatus(slot).outcome === SlotOutcome.EvalFailed && slotStatus(slot).shown === SlotShown.Guest, shown(slot);
	assert identity(slot) === mounted, `${shown(slot)} after ${mounted}`;

	errors.length = 0;
	assert load(p, "throwing.ms"), "the throwing edit compiles";
	assert slotStatus(slot).outcome === SlotOutcome.ViewThrew && slotStatus(slot).shown === SlotShown.InertGuest, shown(slot);
	assert identity(slot) === mounted, `${shown(slot)} after ${mounted}`;

	assert !load(p, "noDispatch.ms"), "a program without raiserDispatch is refused";
	assert slotStatus(slot).outcome === SlotOutcome.MissingExports && slotStatus(slot).shown === SlotShown.InertGuest, shown(slot);
	assert identity(slot) === mounted, `${shown(slot)} after ${mounted}`;

	assert load(p, "app.ms"), "the fixed edit compiles";
	const again = slotStatus(slot);
	assert again.outcome === SlotOutcome.Mounted && again.shown === SlotShown.Guest, shown(slot);
	const old = first.root as SlotRoot;
	const now = again.root as SlotRoot;
	assert now.key !== old.key && now.generation > old.generation, `${shown(slot)} after ${mounted}`;
	closeSlot(slot);
	errors.length = 0;
}

test "a view that throws on reload shows the compiled fallback, which stays interactive" {
	const p = program();
	const host = mockHost();
	const parent = mockNode("root");
	const [presses, setPresses] = createSignal<int32>(0);
	const fallback = element(<Pressable onPress={(e: NeonEvent): void => { setPresses(presses() + 1); }}>
		<Text>fallback</Text>
	</Pressable>);
	const slot = openSlot(p, "card", [hostString("guest")], host, parent as unknown as HostNode, null, fallback);
	assert mockToString(parent).includes("<text>guest</text>"), mockToString(parent);

	errors.length = 0;
	assert load(p, "throwing.ms"), "the throwing edit compiles";
	assert slotStatus(slot).outcome === SlotOutcome.ViewThrew && slotStatus(slot).shown === SlotShown.Fallback, shown(slot);
	assert mockToString(parent).includes("fallback") && !mockToString(parent).includes("guest"), mockToString(parent);
	tap(find(parent, "pressable", 0));
	assert presses() === 1, `the compiled handler ran ${presses()} times`;

	errors.length = 0;
	assert load(p, "app.ms"), "the fixed edit compiles";
	assert slotStatus(slot).shown === SlotShown.Guest, shown(slot);
	assert mockToString(parent).includes("<text>guest</text>") && !mockToString(parent).includes("fallback"), mockToString(parent);
	assert errors.length === 0, errors.join("\n");
	closeSlot(slot);
	assert parent.children.length === 0, mockToString(parent);
}

test "an editor guest's HostPlace is announced, and an app slot opened there mounts inside the editor's tree" {
	const app = program();
	const editor = editorProgram();
	const seen = embed(editor, app);
	const root = mockNode("root");
	const slot = openSlot(editor, "editor", [], mockHost(), root as unknown as HostNode, null);
	assert seen.log.join("; ") === "place preview", seen.log.join("; ");
	const place = seen.place as MockNode;
	assert inside(place, root) && mockToString(root).includes("<text>editor</text>"), mockToString(root);
	assert mockToString(place).includes("<text>app</text>"), mockToString(root);
	tap(find(place, "pressable", 0));
	assert mockToString(place).includes("<text>pressed 1</text>"), mockToString(place);
	closeSlot(slot);
	assert seen.log.join("; ") === `place preview; ${GONE}`, seen.log.join("; ");
	assert root.children.length === 0, mockToString(root);
	assert errors.length === 0, errors.join("\n");
}

test "an editor that drops its place notifies onPlaceGone before the node is released, and closeSlot there succeeds" {
	const app = program();
	const editor = loaded(opened(), "editor.ms");
	const seen = embed(editor, app);
	const root = mockNode("root");
	const slot = openSlot(editor, "listed", [], mockHost(), root as unknown as HostNode, null);
	assert seen.log.join("; ") === "place preview", seen.log.join("; ");
	const place = seen.place as MockNode;
	const dropped = callGuest(editor, "dropPlaces", []);
	assert dropped.ok, dropped.ok ? "" : dropped.error;
	assert seen.log.join("; ") === `place preview; ${GONE}`, seen.log.join("; ");
	assert (seen.slot as SlotHandle).closed && !inside(place, root), mockToString(root);
	assert mockToString(root).includes("<text>editor</text>") && !mockToString(root).includes("app"), mockToString(root);
	closeSlot(slot);
	assert errors.length === 0, errors.join("\n");
}

test "a place name declared twice in one program is refused by name" {
	const app = program();
	const editor = editorProgram();
	const seen = embed(editor, app);
	errors.length = 0;
	const slot = openSlot(editor, "twoPlaces", [], mockHost(), mockNode("root") as unknown as HostNode, null);
	assert errors.length === 1 && errors[0].includes("preview") && errors[0].includes("twice"), errors.join("\n");
	assert slotStatus(slot).outcome === SlotOutcome.ViewThrew && seen.log.length === 0, `${shown(slot)} ${seen.log.join("; ")}`;
	closeSlot(slot);
	errors.length = 0;
}

test "disposing the editor's root notifies onPlaceGone while the place is still in the tree" {
	const app = program();
	const editor = editorProgram();
	const seen = embed(editor, app);
	const [editing, setEditing] = createSignal(true);
	const root = mockNode("root");
	const unmount = render(element(<View>
		<Show when={editing}><GuestSlot program={editor} view="editor" /></Show>
	</View>), mockHost(), root as unknown as HostNode);
	assert seen.log.join("; ") === "place preview", seen.log.join("; ");
	setEditing(false);
	flush();
	assert seen.log.join("; ") === `place preview; ${GONE}`, seen.log.join("; ");
	assert mockToString(root) === "<root><view></view></root>", mockToString(root);
	assert errors.length === 0, errors.join("\n");
	unmount();
}

test "an editor reload notifies onPlaceGone for the old place before announcing the new one" {
	const app = program();
	const editor = editorProgram();
	const seen = embed(editor, app);
	const root = mockNode("root");
	const slot = openSlot(editor, "editor", [], mockHost(), root as unknown as HostNode, null);
	const old = seen.place as MockNode;
	assert loadGuest(editor, "tests/platform/raiser/editor.ms").ok, "the editor reloads";
	assert seen.log.join("; ") === `place preview; ${GONE}; place preview`, seen.log.join("; ");
	const place = seen.place as MockNode;
	assert place !== old && !inside(old, root) && inside(place, root), mockToString(root);
	assert mockToString(place).includes("<text>app</text>"), mockToString(root);
	closeSlot(slot);
	assert errors.length === 0, errors.join("\n");
}
