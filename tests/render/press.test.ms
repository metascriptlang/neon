// Pressable and Text run RN Pressability (500ms long press, 130ms minimum hold,
// long press swallows the press, press rect, cancelable termination) over the
// responder system. Time is the language's real std timer (setTimeout on every
// lane), so each cell awaits past a threshold with wide margins: "not yet" is
// checked at ≥60ms before the deadline, "fired" at ≥30ms after it. Gesture
// callbacks record into a signal: no mutable local is read after an await.

import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { sleepAsync } from "std/core/promise";
import { element } from "../../src/macros/ui/element";
import { NeonEvent, neonEvent, eventType } from "../../src/render/event";
import { Host, MeasureRect, MeasureError } from "../../src/render/hostTypes";
import {
	HostNode, MockNode, mockNode, mockHost, render, fireEvent, fireEventWith, fireTouch,
} from "../../src/render/host";
import { Pressable, Text, View } from "../../src/components/primitives";
import { flush } from "../../src/core/runtime";

let clock = 1000.0;

function touch(node: MockNode, name: string, x: number = 10, y: number = 10): void {
	clock += 10;
	fireTouch(node, name, x, y, clock);
	flush();
}

function tap(node: MockNode): void {
	touch(node, "onTouchStart");
	touch(node, "onTouchEnd");
}

// The click a host sends after the release that already pressed.
function pointerClick(node: MockNode): void {
	const e = neonEvent(eventType("onPress"));
	e.pointerOrigin = true;
	fireEventWith(node, "onPress", e);
	flush();
}

function measuredHost(rect: MeasureRect): Host {
	const host = mockHost();
	host.measureInWindow = (node: HostNode): Result<MeasureRect, MeasureError> => Result.ok(rect);
	return host;
}

test "Pressable is a responder: the release presses once and the host's pointer click is not a second press" {
	const host = mockHost();
	const root = mockNode("root");
	let hits = 0;
	createRoot((): void => {
		render(element(<Pressable onPress={(e: NeonEvent): void => { hits = hits + 1; }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});
	const btn = root.children[0];
	const names = btn.events.map((e) => e.name).join(",");
	assert names === "onTouchStart,onTouchMove,onTouchEnd,onTouchCancel,onPress", "routes " + names;
	touch(btn, "onTouchStart");
	assert hits === 0, "no press on down";
	touch(btn, "onTouchEnd");
	assert hits === 1, "press on release: " + hits.toString();
	pointerClick(btn);
	assert hits === 1, "pointer click after release: " + hits.toString();
	fireEvent(btn, "onPress");
	flush();
	assert hits === 2, "semantic activation presses: " + hits.toString();
}

test "press in and out bracket the gesture" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog((p: string): string => p + s); };
	createRoot((): void => {
		render(element(<Pressable
			onPressIn={(e: NeonEvent): void => { say("in;"); }}
			onPressOut={(e: NeonEvent): void => { say("out;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	touch(btn, "onTouchStart");
	assert log() === "in;", "after down: " + log();

	// Released before the minimum hold: pressOut waits, press does not.
	touch(btn, "onTouchEnd");
	assert log() === "in;press;", "after up: " + log();

	await sleepAsync(250);
	flush();
	assert log() === "in;press;out;", "after min hold: " + log();
}

test "a hold past 500ms fires onLongPress and swallows the press" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog((p: string): string => p + s); };
	createRoot((): void => {
		render(element(<Pressable
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	touch(btn, "onTouchStart");
	await sleepAsync(280);
	flush();
	assert log() === "", "too early: " + log();

	await sleepAsync(400);
	flush();
	assert log() === "long;", "at 500ms: " + log();

	touch(btn, "onTouchEnd");
	assert log() === "long;", "press must be swallowed, got: " + log();
}

test "a short tap with a long press handler still presses" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog((p: string): string => p + s); };
	createRoot((): void => {
		render(element(<Pressable
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	tap(root.children[0]);
	await sleepAsync(600);
	flush();
	assert log() === "press;", "short tap: " + log();
}

test "leaving the press rect deactivates without pressing and coming back activates again" {
	const host = measuredHost({ x: 0, y: 0, width: 100, height: 50 });
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog((p: string): string => p + s); };
	createRoot((): void => {
		render(element(<Pressable
			onPressIn={(e: NeonEvent): void => { say("in;"); }}
			onPressOut={(e: NeonEvent): void => { say("out;"); }}
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	touch(btn, "onTouchStart");
	await sleepAsync(160);
	touch(btn, "onTouchMove", 115, 75);
	assert log() === "in;", "inside the default retention offsets: " + log();
	touch(btn, "onTouchMove", 125, 10);
	assert log() === "in;out;", "past the right offset: " + log();
	touch(btn, "onTouchMove", 50, 20);
	assert log() === "in;out;in;", "back inside: " + log();
	touch(btn, "onTouchMove", 50, 90);
	touch(btn, "onTouchEnd", 50, 90);
	await sleepAsync(650);
	flush();
	assert log() === "in;out;in;out;", "released outside, and moving cancelled the long press: " + log();
}

test "hitSlop widens the press rect" {
	const host = measuredHost({ x: 0, y: 0, width: 100, height: 50 });
	const root = mockNode("root");
	let hits = 0;
	createRoot((): void => {
		render(element(<Pressable hitSlop={30} onPress={(e: NeonEvent): void => { hits += 1; }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});
	const btn = root.children[0];
	touch(btn, "onTouchStart");
	touch(btn, "onTouchMove", 145, 10);
	touch(btn, "onTouchEnd", 145, 10);
	assert hits === 1, "inside slop plus offset: " + hits.toString();
}

test "a parent that claims the move terminates the press, unless the Pressable is not cancelable" {
	let result = "";
	for (const cancelable of [true, false]) {
		const root = mockNode("root");
		const [log, setLog] = createSignal("");
		const say = (s: string): void => { setLog((p: string): string => p + s); };
		let parent = "";
		createRoot((): void => {
			render(element(<View onMoveShouldSetResponderCapture={(): boolean => true}
				onResponderGrant={(): boolean => { parent += "claim;"; return false; }}
				onResponderReject={(): void => { parent += "reject;"; }}>
				<Pressable cancelable={cancelable}
					onPressIn={(e: NeonEvent): void => { say("in;"); }}
					onPressOut={(e: NeonEvent): void => { say("out;"); }}
					onPress={(e: NeonEvent): void => { say("press;"); }}><Text>go</Text></Pressable>
			</View>), mockHost(), root as unknown as HostNode);
		});
		const btn = root.children[0].children[0];
		touch(btn, "onTouchStart");
		await sleepAsync(160);
		touch(btn, "onTouchMove", 12, 30);
		touch(btn, "onTouchEnd", 12, 30);
		pointerClick(btn);
		result += parent + log() + "|";
	}
	assert result === "claim;in;out;|reject;in;out;press;|", result;
}

test "a custom delayLongPress is honored" {
	const host = mockHost();
	const root = mockNode("root");
	const [log, setLog] = createSignal("");
	const say = (s: string): void => { setLog((p: string): string => p + s); };
	createRoot((): void => {
		render(element(<Pressable
			onLongPress={(e: NeonEvent): void => { say("long;"); }}
			delayLongPress={120}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	touch(btn, "onTouchStart");
	await sleepAsync(60);
	flush();
	assert log() === "", "too early: " + log();
	await sleepAsync(90);
	flush();
	assert log() === "long;", "at 120ms: " + log();
	touch(btn, "onTouchEnd");
}

test "a press drives a signal end to end" {
	const host = mockHost();
	const root = mockNode("root");
	const [count, setCount] = createSignal(0);
	createRoot((): void => {
		render(element(<Pressable
			onPressIn={(e: NeonEvent): void => {}}
			onPress={(e: NeonEvent): void => { setCount((p: int32): int32 => p + 1); }}><Text>go</Text></Pressable>), host, root as unknown as HostNode);
	});

	const btn = root.children[0];
	tap(btn);
	tap(btn);
	assert count() === 2, "count " + count().toString();
}

test "semantic activation presses without feedback or a long press" {
	const root = mockNode("root");
	let log = "";
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<Pressable
			onPressIn={(): void => { log += "in;"; }}
			onPressOut={(): void => { log += "out;"; }}
			onLongPress={(): void => { log += "long;"; }}
			onPress={(): void => { log += "press;"; }} />), mockHost(), root as unknown as HostNode);
		return end;
	});
	fireEvent(root.children[0], "onPress");
	flush();
	assert log === "press;", "semantic activation: " + log;
	dispose();
}

test "a long press keeps the release's click suppressed while a later semantic activation presses" {
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
	touch(button, "onTouchStart");
	await sleepAsync(180);
	touch(button, "onTouchEnd");
	pointerClick(button);
	assert log() === "long;", "long then duplicate: " + log();
	fireEvent(button, "onPress");
	flush();
	assert log() === "long;press;", "semantic activation: " + log();
	dispose();
}

test "a cancelled touch never presses" {
	const root = mockNode("root");
	let hits = 0;
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<Pressable onPress={(): void => { hits += 1; }} />), mockHost(), root as unknown as HostNode);
		return end;
	});
	const button = root.children[0];
	touch(button, "onTouchStart");
	touch(button, "onTouchCancel");
	pointerClick(button);
	assert hits === 0, "cancel must not press";
	dispose();
}

test "a pressable Text is a responder too, and the innermost pressable takes the touch" {
	const root = mockNode("root");
	let log = "";
	const dispose = createRoot((end: () => void): () => void => {
		render(element(<Pressable onPress={(): void => { log += "outer;"; }}>
			<Text onPress={(): void => { log += "text;"; }}>go</Text>
		</Pressable>), mockHost(), root as unknown as HostNode);
		return end;
	});
	const label = root.children[0].children[0];
	tap(label);
	assert log === "text;", "innermost: " + log;
	tap(root.children[0]);
	assert log === "text;outer;", "outer alone: " + log;
	dispose();
}
