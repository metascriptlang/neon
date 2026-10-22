import { createVoidHostWith, VoidHost, VoidNode } from "../../src/platform/void/host";
import { Scene2D, NodeRef, localToGlobal, text } from "../../../void/src/void2d/node";
import { xForIndex, lineBoxAt, textWidth } from "../../../void/src/void2d/render";
import { create } from "../../../void/src/void2d/scene";
import { rgba, vec2 } from "../../../void/src/void2d/types";
import { DEFAULT_FONT, addFont } from "../../../void/src/void2d/font";
import { createRoot } from "../../src/core/owner";
import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, render } from "../../src/render/host";
import { Host, NeonNode, TextSpan } from "../../src/render/hostTypes";
import { getOwner, flush } from "../../src/core/runtime";
import { Cleanup, Computation } from "../../src/core/types";
import { Pressable, Text, View } from "../../src/components/primitives";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { sleepAsync } from "std/core/promise";

function tapAt(vh: VoidHost, x: float32, y: float32): void {
	vh.clickAt(x, y);
	flush();
}

test "Void down clickAt up activates gesture only on release, and a pointer click alone is no press" {
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
	let hits = 0;
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<Pressable style={{ width: 100, height: 50 }}
			onPressIn={(e: NeonEvent): void => {
				assert e.pointerOrigin, "Void pointerEvent tags down";
			}}
			onPress={(e: NeonEvent): void => {
				assert e.pointerOrigin, "Void pointerEvent tags up";
				hits += 1;
			}} />), vh.host, vh.root);
		return end;
	});
	vh.layout(200.0, 100.0);
	vh.pointerDown(10.0, 10.0, 1);
	vh.clickAt(10.0, 10.0);
	assert hits === 0, "physical down/clickAt must not activate prematurely";
	vh.pointerUp(10.0, 10.0, 1);
	assert hits === 1, "release activates once";
	vh.clickAt(10.0, 10.0);
	assert hits === 1, "additional physical click is not semantic activation";
	dispose();
	vh.clickAt(10.0, 10.0);
	assert hits === 1, "removed gesture routes stay inert";

	const control = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
	const cheap = render(element(<Pressable style={{ width: 100, height: 50 }}
		onPress={(e: NeonEvent): void => {
			assert e.pointerOrigin, "Void clickAt tags physical press";
			hits += 1;
		}} />), control.host, control.root);
	control.layout(200.0, 100.0);
	control.clickAt(10.0, 10.0);
	assert hits === 1, "a pointer click without a touch is no press, as Pressability's onClick ignores pointer clicks";
	tapAt(control, 10.0, 10.0);
	assert hits === 2, "a whole tap presses";
	cheap();
}

test "Void long down clickAt up does not resurrect press" {
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
	const [log, setLog] = createSignal("");
	const dispose = render(element(<Pressable style={{ width: 100, height: 50 }}
		delayLongPress={60}
		onLongPress={(): void => { setLog(log() + "long;"); }}
		onPress={(): void => { setLog(log() + "press;"); }} />), vh.host, vh.root);
	vh.layout(200.0, 100.0);
	vh.pointerDown(10.0, 10.0, 1);
	vh.clickAt(10.0, 10.0);
	await sleepAsync(180);
	vh.pointerUp(10.0, 10.0, 1);
	vh.clickAt(10.0, 10.0);
	assert log() === "long;", "long gesture stays suppressed: " + log();
	dispose();
}

test "Void nested Text and data span physical presses carry producer provenance" {
	for (const data of [false, true]) {
		const font = addFont("../void/assets/font.ttf");
		assert font.ok, "the existing Void test font must load";
		if (!font.ok) { return; }
		const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), font.value);
		let inner = 0;
		let outer = 0;
		let physical = false;
		const [word, setWord] = createSignal("link");
		const press = (e: NeonEvent): void => { inner += 1; physical = e.pointerOrigin; };
		const body = data
			? element(<Text style={{ height: 30 }} onPress={(): void => { outer += 1; }}
				spans={[{ text: "plain " }, { text: word(), onPress: press }, { text: " tail" }]} />)
			: element(<Text style={{ height: 30 }} onPress={(): void => { outer += 1; }}>
				plain <Text onPress={press}>{word()}</Text> tail
			</Text>);
		const dispose = render(element(<View style={{ width: 400 }}>{body}</View>), vh.host, vh.root);
		vh.layout(400.0, 100.0);
		const text = (vh.root as VoidNode).children[0].children[0];
		assert text.para !== null;
		const label = text.para as NodeRef;
		label.textWidth();
		const link = label.localToGlobal(vec2(label.xForIndex(7) + 1.0, label.lineBoxAt(7).top + 2.0));
		tapAt(vh, link.x, link.y);
		assert inner === 1 && outer === 0, "nearest run owns its physical press";
		assert physical, "clickAt must mark a TextSpan press as physical";
		const plain = label.localToGlobal(vec2(label.xForIndex(1) + 1.0, label.lineBoxAt(1).top + 2.0));
		tapAt(vh, plain.x, plain.y);
		assert inner === 1 && outer === 1, "ordinary Text press control";
		press(neonEvent("press"));
		assert inner === 2 && !physical, "direct semantic callback stays semantic";
		setWord("next");
		tapAt(vh, link.x, link.y);
		assert inner === 3 && physical, "reactive paragraph updates keep physical interaction";
		dispose();
		tapAt(vh, link.x, link.y);
		assert inner === 3 && outer === 1, "disposed physical routes stay inert";
	}
}

test "Void cheap and raw ordinary presses retire with owner but unowned listeners stay valid" {
	for (const cheap of [false, true]) {
		const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
		let hits = 0;
		let raw: HostNode | null = null;
		const dispose = createRoot((end: () => void): () => void => {
			if (cheap) {
				Pressable({ style: accessor(() => ({ width: 100, height: 50 })),
					onPress: (): void => { hits += 1; } })(vh.host, vh.root, null);
			} else {
				const node = vh.host.createElement("view");
				raw = node;
				vh.host.setStyle(node, { width: 100, height: 50 });
				vh.host.addEvent(node, "onPress", (): void => { hits += 1; });
				vh.host.append(vh.root, node);
			}
			return end;
		});
		vh.layout(200.0, 100.0);
		tapAt(vh, 10.0, 10.0);
		assert hits === 1;
		dispose();
		tapAt(vh, 10.0, 10.0);
		assert hits === 1, "ordinary owner cleanup must retire retained-node callbacks";
		if (raw !== null) {
			vh.host.addEvent(raw as HostNode, "onPress", (): void => { hits += 1; });
			tapAt(vh, 10.0, 10.0);
			assert hits === 2, "raw unowned registration has no ownerless cleanup throw";
			vh.host.removeChild(vh.root, raw as HostNode);
			tapAt(vh, 10.0, 10.0);
			assert hits === 2, "physical removal retires an unowned registration";
		}
	}
}

test "Void snapshot dispatch skips a later ordinary entry disposed by an earlier handler" {
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
	const node = vh.host.createElement("view");
	vh.host.setStyle(node, { width: 100, height: 50 });
	vh.host.append(vh.root, node);
	let second: (() => void) | null = null;
	let hits = 0;
	const first = createRoot((end: () => void): () => void => {
		vh.host.addEvent(node, "onPress", (): void => { (second as () => void)(); });
		return end;
	});
	second = createRoot((end: () => void): () => void => {
		vh.host.addEvent(node, "onPress", (): void => { hits += 1; });
		return end;
	});
	vh.layout(200.0, 100.0);
	vh.clickAt(10.0, 10.0);
	assert hits === 0, "snapshot retains entry object but not activation authority";
	first();
}

test "Void Text interaction follows creation owner across updates without mutating shared span data" {
	const font = addFont("../void/assets/font.ttf");
	assert font.ok;
	if (!font.ok) { return; }
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), font.value);
	let hits = 0;
	const press = (e: NeonEvent): void => { assert e.pointerOrigin; hits += 1; };
	const shared: TextSpan[] = [{ text: "link", onPress: press }];
	const next: TextSpan[] = [{ text: "next", onPress: press }];
	const mountSpans = vh.host.paragraph as (host: Host, node: HostNode, before: HostNode | null, kids: NeonNode | null, spans: Accessor<TextSpan[]> | null) => void;
	const [firstSpans, setFirstSpans] = createSignal<TextSpan[]>(shared, { equals: false });
	let firstNode: HostNode | null = null;
	let secondNode: HostNode | null = null;
	let firstOwner: Computation | null = null;
	const first = createRoot((end: () => void): () => void => {
		firstOwner = getOwner();
		const node = vh.host.createElement("text");
		firstNode = node;
		vh.host.setStyle(node, { width: 100, height: 30 });
		vh.host.append(vh.root, node);
		mountSpans(vh.host, node, null, null, firstSpans);
		return end;
	});
	const mountCleanups = ((firstOwner as Computation).disposal as Cleanup[]).length;
	const second = createRoot((end: () => void): () => void => {
		const node = vh.host.createElement("text");
		secondNode = node;
		vh.host.setStyle(node, { width: 100, height: 30 });
		vh.host.append(vh.root, node);
		mountSpans(vh.host, node, null, null, accessor((): TextSpan[] => shared));
		return end;
	});
	for (let i = 0; i < 100; i += 1) { setFirstSpans(next); flush(); }
	const cleanups = (firstOwner as Computation).disposal;
	assert cleanups !== null && cleanups.length === mountCleanups, "mount cleanups, not one per assignment";
	vh.layout(200.0, 150.0);
	const label = (firstNode as VoidNode).para as NodeRef;
	const at = label.localToGlobal(vec2(label.xForIndex(1) + 1.0, label.lineBoxAt(1).top + 2.0));
	vh.clickAt(at.x, at.y);
	assert hits === 1, "the latest spans keep their press";
	first();
	vh.clickAt(at.x, at.y);
	assert hits === 1 && label.text() === "next", "mount cleanup retires latest interaction, not paint";
	const other = (secondNode as VoidNode).para as NodeRef;
	const there = other.localToGlobal(vec2(other.xForIndex(1) + 1.0, other.lineBoxAt(1).top + 2.0));
	vh.clickAt(there.x, there.y);
	assert hits === 2 && shared[0].onPress === press && next[0].onPress === press;
	second();
	vh.clickAt(there.x, there.y);
	assert hits === 2, "shared span data does not share node lifetime";
	const raw = vh.host.createElement("text");
	vh.host.setStyle(raw, { width: 100, height: 30 });
	vh.host.append(vh.root, raw);
	const rawSetter = createRoot((end: () => void): () => void => { mountSpans(vh.host, raw, null, null, accessor((): TextSpan[] => shared)); return end; });
	rawSetter();
	vh.layout(200.0, 150.0);
	const rawLabel = (raw as VoidNode).para as NodeRef;
	const rawAt = rawLabel.localToGlobal(vec2(rawLabel.xForIndex(1) + 1.0, rawLabel.lineBoxAt(1).top + 2.0));
	vh.clickAt(rawAt.x, rawAt.y);
	assert hits === 3, "a raw unowned node remains caller-owned";
	vh.host.removeChild(vh.root, raw);
	vh.clickAt(rawAt.x, rawAt.y);
	assert hits === 3, "physical removal stops unowned interaction";
}
