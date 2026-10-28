import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { NeonEvent, neonEvent, stopPropagation, DOM_DELTA_LINE } from "../../src/render/event";
import { AreaLayer, AreaPointerKind } from "../../src/render/voidAreaHandle";
import { View, Pressable } from "../../src/components/primitives";
import { createVoidHostWith, VoidHost } from "../../src/platform/void/host";
import { Scene2D } from "../../../void/src/void2d/node";
import { create } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { DEFAULT_FONT } from "../../../void/src/void2d/font";

function host(): VoidHost {
	return createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
}

function press(vh: VoidHost, x: float32, y: float32): void {
	vh.pointerDown(x, y, 1);
	vh.pointerUp(x, y, 1);
}

function drag(vh: VoidHost, fromX: float32, fromY: float32, toX: float32, toY: float32): void {
	vh.pointerDown(fromX, fromY, 1);
	vh.pointerMove(toX, toY, 1, true);
	vh.pointerUp(toX, toY, 1);
}

function note(log: string[], what: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => { log.push(what); };
}

test "a press goes to the innermost pressable under the pointer, once" {
	const vh = host();
	const log: string[] = [];
	render(element(
		<Pressable style={{ width: 200, height: 100 }} onPress={note(log, "outer")}>
			<Pressable style={{ width: 100, height: 50 }} onPress={note(log, "inner")} />
		</Pressable>
	), vh.host, vh.root);
	vh.layout(200.0, 100.0);
	press(vh, 10.0, 10.0);
	assert log.join("|") === "inner", "inside the inner one: " + log.join("|");
	log.length = 0;
	press(vh, 150.0, 80.0);
	assert log.join("|") === "outer", "outside the inner one: " + log.join("|");
	log.length = 0;
	vh.clickAt(10.0, 10.0);
	assert log.join("|") === "inner", "clickAt presses the same way: " + log.join("|");
}

test "a pressable drawn over another takes the press alone" {
	const vh = host();
	const log: string[] = [];
	render(element(
		<View style={{ width: 200, height: 100 }}>
			<Pressable style={{ width: 200, height: 100 }} onPress={note(log, "content")} />
			<Pressable style={{ position: "absolute", left: 0, top: 0, width: 60, height: 30 }} onPress={note(log, "hud")} />
		</View>
	), vh.host, vh.root);
	vh.layout(200.0, 100.0);
	press(vh, 10.0, 10.0);
	assert log.join("|") === "hud", "the HUD is on top: " + log.join("|");
	log.length = 0;
	press(vh, 100.0, 60.0);
	assert log.join("|") === "content", "beside the HUD: " + log.join("|");
}

test "a press dragged off its node and released elsewhere does not fire" {
	const vh = host();
	const log: string[] = [];
	render(element(
		<View style={{ width: 300, height: 100, flexDirection: "row" }}>
			<Pressable style={{ width: 100, height: 100 }} onPress={note(log, "a")}>
				<View style={{ width: 50, height: 50 }} />
			</Pressable>
			<Pressable style={{ width: 100, height: 100 }} onPress={note(log, "b")} />
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	drag(vh, 10.0, 10.0, 250.0, 50.0);
	assert log.length === 0, "released on empty space: " + log.join("|");
	drag(vh, 10.0, 10.0, 150.0, 50.0);
	assert log.length === 0, "released on another pressable: " + log.join("|");
	drag(vh, 80.0, 80.0, 10.0, 10.0);
	assert log.join("|") === "a", "released on a child of the pressed node: " + log.join("|");
	log.length = 0;
	vh.pointerDown(10.0, 10.0, 3);
	vh.pointerUp(10.0, 10.0, 3);
	assert log.length === 0, "a secondary button does not press: " + log.join("|");
}

test "a gesture pressable cancels when the pointer leaves it, and only the innermost one presses" {
	const vh = host();
	const log: string[] = [];
	render(element(
		<View style={{ width: 300, height: 100 }}>
			<Pressable style={{ width: 200, height: 100 }} onPressIn={note(log, "outer in")} onPress={note(log, "outer")}>
				<Pressable style={{ width: 100, height: 50 }} onPressIn={note(log, "inner in")} onPress={note(log, "inner")} />
			</Pressable>
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	press(vh, 10.0, 10.0);
	assert log.join("|") === "inner in|inner", "nested: " + log.join("|");
	log.length = 0;
	drag(vh, 10.0, 10.0, 250.0, 50.0);
	assert log.join("|") === "inner in", "dragged off, the press is cancelled: " + log.join("|");
}

test "stopPropagation stops a pointer event at the node that calls it" {
	const vh = host();
	const log: string[] = [];
	render(element(
		<View style={{ width: 200, height: 100 }} onPointerDown={note(log, "outer")}>
			<View style={{ width: 100, height: 50 }} onPointerDown={(e: NeonEvent): void => { log.push("inner"); e.stopPropagation(); }} />
		</View>
	), vh.host, vh.root);
	vh.layout(200.0, 100.0);
	vh.pointerDown(10.0, 10.0, 1);
	vh.pointerUp(10.0, 10.0, 1);
	assert log.join("|") === "inner", "the outer node does not hear it: " + log.join("|");
}

test "a View responder is granted, moves, releases and is terminated on the Void pointer stream" {
	const vh = host();
	const log: string[] = [];
	render(element(
		<View style={{ width: 200, height: 100 }}
			onStartShouldSetResponder={(e: NeonEvent): boolean => true}
			onResponderGrant={(e: NeonEvent): boolean => { log.push("grant"); return false; }}
			onResponderMove={(e: NeonEvent): void => { log.push(`move ${e.x}`); }}
			onResponderRelease={(e: NeonEvent): void => { log.push("release"); }}
			onResponderTerminate={(e: NeonEvent): void => { log.push("terminate"); }}
			onTouchCancel={(e: NeonEvent): void => { log.push("touchcancel"); }} />
	), vh.host, vh.root);
	vh.layout(200.0, 100.0);
	vh.pointerDown(10.0, 10.0, 1);
	vh.pointerMove(40.0, 10.0, 1, true);
	vh.pointerMove(300.0, 10.0, 1, true);
	vh.pointerUp(300.0, 10.0, 1);
	vh.pointerMove(50.0, 10.0, 0, false);
	assert log.join("|") === "grant|move 40|move 300|release", "a whole touch: " + log.join("|");
	log.length = 0;
	vh.pointerDown(10.0, 10.0, 1);
	vh.setWindowFocus(false);
	vh.pointerUp(10.0, 10.0, 1);
	assert log.join("|") === "grant|terminate|touchcancel", "losing the window cancels: " + log.join("|");
}

test "a pressable hears hover in and out once per entry, one hovered target per pointer" {
	const vh = host();
	const log: string[] = [];
	render(element(
		<View style={{ width: 300, height: 100, flexDirection: "row" }}>
			<Pressable style={{ width: 100, height: 100 }} onHoverIn={note(log, "a in")} onHoverOut={note(log, "a out")} />
			<Pressable style={{ width: 100, height: 100 }} onHoverIn={note(log, "b in")} onHoverOut={note(log, "b out")} />
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	vh.pointerMove(10.0, 10.0, 0, false);
	vh.pointerMove(20.0, 10.0, 0, false);
	vh.pointerMove(150.0, 10.0, 0, false);
	vh.pointerMove(250.0, 10.0, 0, false);
	vh.pointerMove(50.0, 10.0, 0, false);
	vh.pointerLeave();
	assert log.join("|") === "a in|a out|b in|b out|a in|a out", log.join("|");
}

class Mark {}

function fakeLayer(name: string, takes: (x: float32, y: float32) => boolean, log: string[]): AreaLayer {
	return {
		anchor: { node: new Mark(), inText: false },
		layout: (pixelWidth: int32, pixelHeight: int32): void => {},
		prepare: (pixelWidth: int32, pixelHeight: int32): void => {},
		draw: (): void => {},
		hit: (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent): boolean => {
			const taken = kind === AreaPointerKind.Leave || takes(x, y);
			if (taken || e.pressed || e.type === "pointerup") { log.push(`${name} ${kind.toString()} ${e.type} ${x},${y}`); }
			return taken;
		},
	};
}

test "a layer hears what no 2D handler takes, top layer first, and keeps a press it took" {
	const vh = host();
	const log: string[] = [];
	render(element(
		<View style={{ width: 300, height: 100 }}>
			<Pressable style={{ width: 50, height: 50 }} onPress={note(log, "hud")} onHoverIn={note(log, "hud in")} />
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	const everywhere = (x: float32, y: float32): boolean => true;
	const right = (x: float32, y: float32): boolean => x > 200.0;
	const bottom = fakeLayer("bottom", everywhere, log);
	const top = fakeLayer("top", right, log);
	vh.setLayers((): AreaLayer[] => [bottom, top]);
	press(vh, 10.0, 10.0);
	assert log.join("|") === "hud in|hud", "2D takes its own press: " + log.join("|");
	log.length = 0;
	vh.pointerDown(250.0, 50.0, 1);
	vh.pointerMove(10.0, 10.0, 1, true);
	vh.pointerUp(10.0, 10.0, 1);
	assert log.join("|") === "top Button pointerdown 250,50|top Motion pointermove 10,10|top Button pointerup 10,10",
		"the top layer took the press and kept it over the HUD: " + log.join("|");
	log.length = 0;
	vh.pointerMove(100.0, 50.0, 0, false);
	vh.pointerMove(250.0, 50.0, 0, false);
	vh.pointerMove(10.0, 10.0, 0, false);
	assert log.join("|") === "bottom Motion pointermove 100,50|top Motion pointermove 250,50|bottom Leave pointerleave 250,50"
		+ "|top Leave pointerleave 10,10|hud in", "hover moves between layers and back to 2D: " + log.join("|");
	log.length = 0;
	vh.wheel(100.0, 50.0, 0.0, 1.0, DOM_DELTA_LINE);
	assert log.join("|") === "bottom Wheel wheel 100,50", "a wheel no 2D node takes: " + log.join("|");
}
