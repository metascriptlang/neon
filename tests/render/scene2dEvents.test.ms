import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { AreaLayer, AreaPointerKind } from "../../src/render/voidAreaHandle";
import { Void } from "../../src/components/primitives";
import { Scene2D, Group, Rect } from "../../src/components/scene2d";
import { Local2D } from "../../../void/src/void2d/node";
import { rgba } from "../../../void/src/void2d/types";

function translated(x: float32, y: float32): Local2D {
	return { x: x, y: y, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0 };
}

function pointer(type: string, pressed: boolean): NeonEvent {
	const e = neonEvent(type);
	e.button = 1;
	e.pressed = pressed;
	return e;
}

function layerOf(root: MockNode): AreaLayer {
	const layers = mockAreaHub(root.children[0]).layers();
	if (layers.length !== 1) { throw new Error("fixture: expected one Scene2D layer, got " + layers.length.toString()); }
	return layers[0];
}

function hits(layer: AreaLayer, x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent): boolean {
	const hit = layer.hit;
	if (hit === null) { throw new Error("the Scene2D layer has no hit hook"); }
	return (hit as (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent) => boolean)(x, y, kind, e);
}

function tap(layer: AreaLayer, x: float32, y: float32): boolean {
	const took = hits(layer, x, y, AreaPointerKind.Button, pointer("pointerdown", true));
	hits(layer, x, y, AreaPointerKind.Button, pointer("pointerup", false));
	return took;
}

function note(log: string[], what: string): () => void {
	return (): void => { log.push(what); };
}

test "a Scene2D node takes press and hover props through the layer's hit hook, innermost first" {
	const log: string[] = [];
	const root = mockNode("root");
	render(element(<Void>
		<Scene2D>
			<Group local={translated(100.0, 100.0)} onPress={note(log, "group")}>
				<Rect width={50.0} height={50.0} color={rgba(1.0, 0.0, 0.0, 1.0)} onPress={note(log, "rect")}
					onHoverIn={note(log, "rect in")} onHoverOut={note(log, "rect out")} />
			</Group>
			<Rect local={translated(300.0, 0.0)} width={20.0} height={20.0} color={rgba(0.0, 1.0, 0.0, 1.0)} />
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	assert tap(layer, 110.0, 110.0), "the rect takes the press";
	assert log.join("|") === "rect in|rect", "only the innermost node presses: " + log.join("|");
	log.length = 0;
	assert !tap(layer, 10.0, 10.0), "empty space is left to the layers below";
	assert !tap(layer, 305.0, 5.0), "a node with no handler is left to the layers below";
	assert log.join("|") === "rect out", "leaving the rect: " + log.join("|");
}

test "a Scene2D node runs Pressable's state machine: press in, then a drag off cancels" {
	const log: string[] = [];
	const root = mockNode("root");
	render(element(<Void>
		<Scene2D>
			<Rect width={50.0} height={50.0} color={rgba(1.0, 0.0, 0.0, 1.0)}
				onPressIn={note(log, "in")} onPress={note(log, "press")} />
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	tap(layer, 10.0, 10.0);
	assert log.join("|") === "in|press", "a tap: " + log.join("|");
	log.length = 0;
	assert hits(layer, 10.0, 10.0, AreaPointerKind.Button, pointer("pointerdown", true)), "down";
	hits(layer, 200.0, 200.0, AreaPointerKind.Motion, pointer("pointermove", true));
	hits(layer, 200.0, 200.0, AreaPointerKind.Button, pointer("pointerup", false));
	assert log.join("|") === "in", "dragged off: " + log.join("|");
}
