import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { NeonEvent } from "../../src/render/event";
import { createSignal } from "../../src/core/signal";
import { sleepAsync } from "std/core/promise";
import { Pressable, Text, View, ScrollView } from "../../src/components/primitives";
import { TouchableOpacity } from "../../src/components/touchable";

extern class HTMLElement {
	tagName: string;
}

function probe(node: HostNode): HTMLElement {
	return node as unknown as HTMLElement;
}

extern function find(label: cstring): HTMLElement from
	"document.querySelector('[aria-label=\"' + # + '\"]')";
extern function semantic(node: HTMLElement, mode: cstring): number from
	"((n, m) => { if (m === 'programmatic') { n.click(); return -1; } const e = m === 'mouse' ? new MouseEvent('click', {bubbles: true}) : new PointerEvent('click', {bubbles: true, pointerType: m === 'empty' ? '' : m}); n.dispatchEvent(e); return e.timeStamp; })(#, #)";
extern function pointer(node: HTMLElement, phase: cstring): void from
	"#.dispatchEvent(new PointerEvent(#, {bubbles: true, pointerType: 'mouse', pointerId: 1, clientX: 10, clientY: 10}))";
extern function childTextClick(node: HTMLElement): void from "#.firstChild.click()";
extern function focusInputAndClick(node: HTMLElement): boolean from
	"((n) => { const input = document.createElement('input'); document.body.appendChild(input); input.focus(); n.click(); const kept = document.activeElement === input; input.remove(); return kept; })(#)";
extern function opacity(node: HTMLElement): string from "#.style.opacity";

test "DOM gesture semantic MouseEvent programmatic and empty pointerType activate without feedback" {
	const [log, setLog] = createSignal("");
	const dispose = render(element(<Pressable accessibilityLabel="activation-semantic"
		onPressIn={(): void => { setLog(log() + "in;"); }}
		onPressOut={(): void => { setLog(log() + "out;"); }}
		onLongPress={(): void => { setLog(log() + "long;"); }} delayLongPress={60}
		onPress={(e: NeonEvent): void => {
			assert !e.pointerOrigin, "semantic input has no pointer provenance";
			setLog(log() + "press;");
		}} />), domHost(), documentBody());
	const button = find("activation-semantic");
	for (const mode of ["programmatic", "mouse", "empty"]) { semantic(button, mode); }
	assert log() === "press;press;press;", "semantic routes: " + log();
	await sleepAsync(180);
	assert log() === "press;press;press;", "no feedback or timer was synthesized: " + log();
	dispose();
}

test "DOM gesture rejects nonempty pointerType duplicates after release and without down" {
	let hits = 0;
	let lastPointerOrigin = false;
	const dispose = render(element(<Pressable accessibilityLabel="activation-physical"
		onPressIn={(): void => {}}
		onPress={(e: NeonEvent): void => {
			lastPointerOrigin = e.pointerOrigin;
			hits += 1;
		}} />), domHost(), documentBody());
	const button = find("activation-physical");
	semantic(button, "mouse");
	assert hits === 1 && !lastPointerOrigin,
		"legacy MouseEvent is logical, not classified by coordinates";
	semantic(button, "pen");
	assert hits === 1, "tagged event without recognition cannot activate";
	pointer(button, "pointerdown");
	pointer(button, "pointerup");
	semantic(button, "pen");
	assert hits === 2 && lastPointerOrigin,
		"physical up plus nonempty pointerType click activates once";
	dispose();
}

test "DOM long-only selected gesture preserves semantic timestamp after a pointer release" {
	let stamp: number = -1;
	let hits = 0;
	const dispose = render(element(<View onTouchStart={(): void => {}}>
		<Pressable accessibilityLabel="activation-stamp"
			onLongPress={(): void => {}}
			onPress={(e: NeonEvent): void => { stamp = e.timeStamp; hits += 1; }} />
	</View>), domHost(), documentBody());
	const button = find("activation-stamp");
	pointer(button, "pointerdown");
	pointer(button, "pointerup");
	await sleepAsync(30);
	const expected = semantic(button, "empty");
	assert stamp === expected, "semantic timestamp must not become lastPointerUp";
	assert hits === 2, "physical release and independent semantic activation";
	dispose();
}

test "DOM nested gesture Pressable text activates nearest owner not its parent" {
	let log = "";
	const dispose = render(element(<Pressable accessibilityLabel="activation-parent"
		onPress={(): void => { log += "parent;"; }}>
		<Pressable accessibilityLabel="activation-child" onPressIn={(): void => {}}
			onPress={(): void => { log += "child;"; }}><Text>nested label</Text></Pressable>
	</Pressable>), domHost(), documentBody());
	childTextClick(find("activation-child"));
	assert log === "child;", "nested text belongs to child: " + log;
	semantic(find("activation-parent"), "programmatic");
	assert log === "child;parent;", "parent still owns its direct activation";
	dispose();
}

test "DOM long-only child without onPress does not activate its Pressable parent" {
	let hits = 0;
	const dispose = render(element(<Pressable accessibilityLabel="activation-passive-parent"
		onPress={(): void => { hits += 1; }}>
		<Pressable accessibilityLabel="activation-passive-child"
			onLongPress={(): void => {}}><Text>long-only label</Text></Pressable>
	</Pressable>), domHost(), documentBody());
	childTextClick(find("activation-passive-child"));
	assert hits === 0, "callback-less child remains semantic owner";
	dispose();
}

test "DOM generic pointer View does not steal its parent semantic press" {
	let hits = 0;
	const dispose = render(element(<Pressable onPress={(): void => { hits += 1; }}>
		<View accessibilityLabel="activation-pointer-view" onPointerDown={(): void => {}}>
			<Text>generic pointer label</Text>
		</View>
	</Pressable>), domHost(), documentBody());
	childTextClick(find("activation-pointer-view"));
	assert hits === 1, "pointer listener is not semantic ownership";
	dispose();
}

test "DOM intrinsic passive press owner is cleaned on removal without a listener" {
	const host = domHost();
	const parent = host.createElement("view");
	const child = host.createElement("pressable");
	let hits = 0;
	host.append(documentBody(), parent);
	host.append(parent, child);
	host.addEvent(parent, "onPress", (): void => { hits += 1; });
	semantic(probe(child), "programmatic");
	assert hits === 0, "intrinsic child owns activation without a callback";
	host.removeChild(parent, child);
	host.append(parent, child);
	semantic(probe(child), "programmatic");
	assert hits === 1, "release removes intrinsic owner registration";
	host.removeChild(documentBody(), parent);
}

test "DOM disabled Touchable child never leaks semantic activation to parent" {
	const [off, setOff] = createSignal(false);
	let log = "";
	const dispose = render(element(<Pressable accessibilityLabel="activation-disabled-parent"
		onPress={(): void => { log += "parent;"; }}>
		<TouchableOpacity accessibilityLabel="activation-disabled-child" disabled={off()}
			onPress={(): void => { log += "child;"; }}><Text>disabled label</Text></TouchableOpacity>
	</Pressable>), domHost(), documentBody());
	const child = find("activation-disabled-child");
	childTextClick(child);
	assert log === "child;", "enabled child";
	setOff(true);
	childTextClick(child);
	assert log === "child;", "disabled child owns click without leaking";
	setOff(false);
	childTextClick(child);
	assert log === "child;child;", "enabled again";
	assert opacity(child) === "1", "semantic activation has no opacity feedback";
	dispose();
}

test "DOM handled ScrollView recognizes gesture semantic owner and retains focused input" {
	let hits = 0;
	const dispose = render(element(<ScrollView keyboardShouldPersistTaps="handled">
		<Pressable accessibilityLabel="activation-handled" onPressIn={(): void => {}}
			onPress={(): void => { hits += 1; }}><Text>handled</Text></Pressable>
	</ScrollView>), domHost(), documentBody());
	assert focusInputAndClick(find("activation-handled")), "registered gesture keeps input focus";
	assert hits === 1, "handled capture permits semantic activation";
	dispose();
}

test "DOM nearest press registration cleanup restores outer ownership" {
	const host = domHost();
	const parent = host.createElement("view");
	const child = host.createElement("text");
	let log = "";
	host.append(documentBody(), parent);
	host.append(parent, child);
	host.addEvent(parent, "onPress", (): void => { log += "parent;"; });
	host.addEvent(child, "onPress", (): void => { log += "child;"; });
	semantic(probe(child), "programmatic");
	assert log === "child;", "nearest registered host owner";
	host.removeChild(parent, child);
	host.append(parent, child);
	semantic(probe(child), "programmatic");
	assert log === "child;parent;", "removed registration and listeners are cleaned";
	host.removeChild(documentBody(), parent);
}
