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
import { NeonEvent } from "../../src/render/event";
import { HostNode, mockNode, mockHost, renderToHost, fireEvent } from "../../src/render/host";
import { Pressable, Text } from "../../src/components/primitives";

test "onPress alone stays on the cheap click path" {
	const host = mockHost();
	const root = mockNode("root");
	let hits = 0;
	createRoot((): void => {
		renderToHost(element(<Pressable onPress={(e: NeonEvent): void => { hits = hits + 1; }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	assert btn.events.length === 1, "listener count " + btn.events.length.toString();
	assert btn.events[0].name === "onPress", "wired " + btn.events[0].name;
	fireEvent(btn, "onPress");
	assert hits === 1, "hits " + hits.toString();
}

test "declaring a gesture prop switches to pointer tracking" {
	const host = mockHost();
	const root = mockNode("root");
	createRoot((): void => {
		renderToHost(element(<Pressable onPressIn={(e: NeonEvent): void => {}}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
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
		renderToHost(element(<Pressable
			onPressIn={(e: NeonEvent): void => { say("in;"); }}
			onPressOut={(e: NeonEvent): void => { say("out;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	assert log() === "in;", "after down: " + log();

	// Released before the minimum hold: pressOut waits, press does not.
	fireEvent(btn, "onPointerUp");
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
		renderToHost(element(<Pressable
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	await sleepAsync(280);
	assert log() === "", "too early: " + log();

	await sleepAsync(400);
	assert log() === "long;", "at 500ms: " + log();

	fireEvent(btn, "onPointerUp");
	assert log() === "long;", "press must be swallowed, got: " + log();
}

test "a short tap with a long press handler still presses" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog(log() + s); };
	createRoot((): void => {
		renderToHost(element(<Pressable
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	fireEvent(btn, "onPointerUp");
	await sleepAsync(300);
	assert log() === "press;", "short tap: " + log();
}

test "leaving the element cancels the press without firing it" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog(log() + s); };
	createRoot((): void => {
		renderToHost(element(<Pressable
			onPressIn={(e: NeonEvent): void => { say("in;"); }}
			onPressOut={(e: NeonEvent): void => { say("out;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	await sleepAsync(60);
	fireEvent(btn, "onPointerLeave");
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
		renderToHost(element(<Pressable
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			delayLongPress={120}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
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
		renderToHost(element(<Pressable
			onPressIn={(e: NeonEvent): void => {}}
			onPress={(e: NeonEvent): void => { setCount(count() + 1); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	fireEvent(btn, "onPointerDown");
	fireEvent(btn, "onPointerUp");
	fireEvent(btn, "onPointerDown");
	fireEvent(btn, "onPointerUp");
	assert count() === 2, "count " + count().toString();
}
