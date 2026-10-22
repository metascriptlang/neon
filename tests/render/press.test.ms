// Pressable's gesture machine, ported from RN Pressability (500ms long press,
// 130ms minimum hold, long press swallows the press). Time is the language's
// real std timer (setTimeout on every lane), so each cell awaits past a
// threshold with wide margins — "not yet" is checked at ≥60ms before the
// deadline, "fired" at ≥30ms after it. Gesture callbacks record into a signal:
// no mutable local is read after an await.

import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { sleepAsync } from "std/core/promise";
import { element } from "../../src/macros/ui/element";
import { NeonEvent, neonEvent, eventType } from "../../src/render/event";
import {
	HostNode, MockNode, mockNode, mockHost, render, fireEvent, fireEventWith,
} from "../../src/render/host";
import { Pressable, Text } from "../../src/components/primitives";
import { flush } from "../../src/core/runtime";

test "onPress alone stays on the cheap click path" {
	const host = mockHost();
	const root = mockNode("root");
	let hits = 0;
	createRoot((): void => {
		render(element(<Pressable onPress={(e: NeonEvent): void => { hits = hits + 1; }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	assert btn.events.length === 1, "listener count " + btn.events.length.toString();
	assert btn.events[0].name === "onPress", "wired " + btn.events[0].name;
	fireEvent(btn, "onPress");
	flush();
	assert hits === 1, "hits " + hits.toString();
}

test "declaring a gesture prop switches to pointer tracking" {
	const host = mockHost();
	const root = mockNode("root");
	createRoot((): void => {
		render(element(<Pressable onPressIn={(e: NeonEvent): void => {}}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	assert btn.events.length === 4, "listener count " + btn.events.length.toString();
	assert btn.events[0].name === "onPointerDown", "first " + btn.events[0].name;
}

test "press in and out bracket the gesture" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog(log() + s); };
	createRoot((): void => {
		render(element(<Pressable
			onPressIn={(e: NeonEvent): void => { say("in;"); }}
			onPressOut={(e: NeonEvent): void => { say("out;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	flush();
	assert log() === "in;", "after down: " + log();

	// Released before the minimum hold: pressOut waits, press does not.
	fireEvent(btn, "onPointerUp");
	flush();
	assert log() === "in;press;", "after up: " + log();

	await sleepAsync(250);
	assert log() === "in;press;out;", "after min hold: " + log();
}

test "a hold past 500ms fires onLongPress and swallows the press" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog(log() + s); };
	createRoot((): void => {
		render(element(<Pressable
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	flush();
	await sleepAsync(280);
	assert log() === "", "too early: " + log();

	await sleepAsync(400);
	assert log() === "long;", "at 500ms: " + log();

	fireEvent(btn, "onPointerUp");
	flush();
	assert log() === "long;", "press must be swallowed, got: " + log();
}

test "a short tap with a long press handler still presses" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog(log() + s); };
	createRoot((): void => {
		render(element(<Pressable
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	flush();
	fireEvent(btn, "onPointerUp");
	flush();
	await sleepAsync(300);
	assert log() === "press;", "short tap: " + log();
}

test "leaving the element cancels the press without firing it" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog(log() + s); };
	createRoot((): void => {
		render(element(<Pressable
			onPressIn={(e: NeonEvent): void => { say("in;"); }}
			onPressOut={(e: NeonEvent): void => { say("out;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	flush();
	await sleepAsync(60);
	fireEvent(btn, "onPointerLeave");
	flush();
	assert log() === "in;", "leave must not press: " + log();

	await sleepAsync(250);
	assert log() === "in;out;", "out after min hold: " + log();

	await sleepAsync(350);
	assert log() === "in;out;", "no late long press: " + log();
}

test "a custom delayLongPress is honored" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog(log() + s); };
	createRoot((): void => {
		render(element(<Pressable
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			delayLongPress={120}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	assert btn.events.length === 4, "long-only without onPress keeps four pointer listeners";
	fireEvent(btn, "onPointerDown");
	flush();
	await sleepAsync(60);
	assert log() === "", "too early: " + log();
	await sleepAsync(90);
	assert log() === "long;", "at 120ms: " + log();
}

test "a press drives a signal end to end" {
	const host = mockHost();
	const root = mockNode("root");
	const [count, setCount] = createSignal(0);
	createRoot((): void => {
		render(element(<Pressable
			onPressIn={(e: NeonEvent): void => {}}
			onPress={(e: NeonEvent): void => { setCount(count() + 1); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	flush();
	fireEvent(btn, "onPointerUp");
	flush();
	fireEvent(btn, "onPointerDown");
	flush();
	fireEvent(btn, "onPointerUp");
	flush();
	assert count() === 2, "count " + count().toString();
}

test "in-out gesture tier accepts independent semantic activation without feedback" {
	const root = mockNode("root");
	let log = "";
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<Pressable
			onPressIn={(): void => { log += "in;"; }}
			onPressOut={(): void => { log += "out;"; }}
			onPress={(): void => { log += "press;"; }} />), mockHost(), root as unknown as HostNode);
		return end;
	});
	fireEvent(root.children[0], "onPress");
	flush();
	assert log === "press;", "semantic activation: " + log;
	assert root.children[0].events.length === 5, "four pointer routes plus semantic press";
	dispose();
}

test "long-only gesture tier accepts semantic activation without a long press" {
	const root = mockNode("root");
	let log = "";
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<Pressable
			onLongPress={(): void => { log += "long;"; }}
			onPress={(): void => { log += "press;"; }} />), mockHost(), root as unknown as HostNode);
		return end;
	});
	fireEvent(root.children[0], "onPress");
	flush();
	assert log === "press;", "semantic activation: " + log;
	dispose();
}

function physical(node: MockNode, name: string): void {
	const e = neonEvent(eventType(name));
	e.pointerOrigin = true;
	fireEventWith(node, name, e);
	flush();
}

test "gesture physical release and tagged click activate once while semantic click stays independent" {
	const root = mockNode("root");
	let hits = 0;
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<Pressable onPressIn={(): void => {}}
			onPress={(): void => { hits += 1; }} />), mockHost(), root as unknown as HostNode);
		return end;
	});
	const button = root.children[0];
	physical(button, "onPointerDown");
	physical(button, "onPress");
	assert hits === 0, "Void ordering must not activate on down/clickAt";
	physical(button, "onPointerUp");
	physical(button, "onPress");
	assert hits === 1, "release and native/browser duplicate: " + hits.toString();
	fireEvent(button, "onPress");
	flush();
	assert hits === 2, "independent semantic activation";
	dispose();
}

test "leave and cancel never resurrect a gesture through a tagged click" {
	for (const cancel of ["onPointerLeave", "onPointerCancel"]) {
		const root = mockNode("root");
		let hits = 0;
		const dispose = createRoot((end: () => void): () => void => {
			render(element(<Pressable onPressIn={(): void => {}}
				onPress={(): void => { hits += 1; }} />), mockHost(), root as unknown as HostNode);
			return end;
		});
		const button = root.children[0];
		physical(button, "onPointerDown");
		physical(button, cancel);
		physical(button, "onPointerUp");
		physical(button, "onPress");
		assert hits === 0, cancel + " must not press";
		fireEvent(button, "onPress");
		flush();
		assert hits === 1, "semantic activation after " + cancel;
		dispose();
	}
}

test "long gesture tagged click stays suppressed but later semantic activation works" {
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<Pressable delayLongPress={60}
			onLongPress={(): void => { setLog((p: string): string => p + "long;"); }}
			onPress={(): void => { setLog((p: string): string => p + "press;"); }} />),
			mockHost(), root as unknown as HostNode);
		return end;
	});
	const button = root.children[0];
	physical(button, "onPointerDown");
	await sleepAsync(180);
	physical(button, "onPointerUp");
	physical(button, "onPress");
	assert log() === "long;", "long then duplicate: " + log();
	fireEvent(button, "onPress");
	flush();
	assert log() === "long;press;", "semantic activation: " + log();
	dispose();
}
