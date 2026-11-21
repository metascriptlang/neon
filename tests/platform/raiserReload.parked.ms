import { render, mockHost, mockNode, mockToString, fireEventWith, fireTouch, MockNode, HostNode } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";
import { neonEvent, eventType } from "../../src/render/event";
import { writeFile, mkdir, realpath } from "std/fs";
import {
	GuestProgram, GuestSlot, Diagnostic, openGuest, closeGuest, saveGuest, loadSavedGuest, reloadSavedGuest, refreshSavedGuest,
} from "../../src/platform/raiser/native";

const errors: string[] = [];
let clock = 1000.0;

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

// A guest project of its own, built with Neon Refresh's module pass under -d:refresh, as a phone preview's app is.
const HOT_DIR = "out/raiserHot";

function neonPath(rel: string): string { return `${realpath(".")}/${rel}`; }

function written(path: string, text: string): void {
	const done = writeFile(path, text);
	if (!done.ok) { throw new Error(`${path}: ${done.error.message}`); }
}

function writeHot(label: string, boxFields: string): void {
	mkdir("out");
	mkdir(HOT_DIR);
	written(`${HOT_DIR}/build.ms`, `const config = { globalImports: [{ from: "${neonPath("src/converters")}", modulePass: "refreshPass" }], defines: { refresh: true } };
export default config;
`);
	written(`${HOT_DIR}/app.ms`, `import { mountGuest } from "${neonPath("src/platform/raiser/guest")}";
import { NeonNode } from "${neonPath("src/render/hostTypes")}";
import { Counter, boxed } from "./view";

export { raiserDispatch, raiserDispose } from "${neonPath("src/platform/raiser/guest")}";

export function counter(root: int32): void {
	mountGuest(root, (): NeonNode => <Counter />);
}

export function box(): int32 { return boxed(); }
`);
	written(`${HOT_DIR}/view.ms`, `import { createSignal } from "${neonPath("src/core/signal")}";
import { NeonEvent } from "${neonPath("src/render/event")}";
import { NeonNode } from "${neonPath("src/render/hostTypes")}";
import { View, Text, Pressable } from "${neonPath("src/components/primitives")}";

class Box { ${boxFields} }

export function boxed(): int32 { return new Box().a; }

export function Counter(): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	const inc: (e: NeonEvent) => void = (e: NeonEvent): void => { setCount(count() + 1); };
	return <View>
		<Text>${label}</Text>
		<Pressable onPress={inc}><Text>{\`count \${count()}\`}</Text></Pressable>
	</View>;
}
`);
}

function hotOpened(): GuestProgram {
	const made = openGuest({ projectRoot: HOT_DIR });
	if (!made.ok) { throw new Error(made.error); }
	const p = made.value;
	p.onError = (message: string): void => { errors.push(message); };
	return p;
}

function hotBytes(editor: GuestProgram): Uint8Array {
	const saved = saveGuest(editor, `${HOT_DIR}/app.ms`);
	if (!saved.ok) { throw new Error(saved.error.map((d) => `${d.file}:${d.line}: ${d.message}`).join("\n")); }
	return saved.value;
}

function messages(r: Result<int32, Diagnostic[]>): string {
	return r.ok ? "" : r.error.map((d) => d.message).join("\n");
}

test "a saved guest reloaded in place shows the edited text and keeps a component's state; a layout change is refused by name" {
	writeHot("v1", "a: int32 = 1;");
	const editor = hotOpened();
	const phone = hotOpened();
	const first = loadSavedGuest(phone, hotBytes(editor));
	assert first.ok, messages(first);
	const root = mockNode("root");
	const unmount = render(element(<GuestSlot program={phone} view="counter" args={[]} />), mockHost(), root as unknown as HostNode);
	const button = find(root, "pressable", 0);
	tap(button);
	tap(button);
	tap(button);
	assert mockToString(root).includes("<text>v1</text>") && mockToString(root).includes("count 3"), mockToString(root);

	writeHot("v2", "a: int32 = 1;");
	const swapped = refreshSavedGuest(phone, hotBytes(editor));
	assert swapped.ok, messages(swapped);
	assert mockToString(root).includes("<text>v2</text>"), `the edited text shows: ${mockToString(root)}`;
	assert mockToString(root).includes("count 3"), `the counter keeps its state: ${mockToString(root)}`;
	tap(find(root, "pressable", 0));
	assert mockToString(root).includes("count 4"), `the kept counter still counts: ${mockToString(root)}`;

	writeHot("v3", "a: int32 = 1; b: int32 = 2;");
	const refused = refreshSavedGuest(phone, hotBytes(editor));
	assert !refused.ok && messages(refused).includes("Box"), `a layout change is refused naming the type: ${messages(refused)}`;
	assert mockToString(root).includes("<text>v2</text>") && mockToString(root).includes("count 4"), `the old tree stays: ${mockToString(root)}`;

	const fresh = reloadSavedGuest(phone, hotBytes(editor));
	assert fresh.ok, messages(fresh);
	assert mockToString(root).includes("<text>v3</text>") && mockToString(root).includes("count 0"), `a fresh reload starts over: ${mockToString(root)}`;
	assert errors.length === 0, errors.join("\n");
	unmount();
	closeGuest(editor);
	closeGuest(phone);
}
