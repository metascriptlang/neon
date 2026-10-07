import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent, fireEventWith, fireTouch } from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { View, Pressable, Text } from "../../src/components/primitives";
import { PanResponder, PanResponderGestureState } from "../../src/components/panResponder";

function mount(app: () => NeonNode): MockNode {
	const root = mockNode("root");
	createRoot((): void => { render(app(), mockHost(), root as unknown as HostNode); });
	return root;
}

function horizontalPan(log: string[]): NeonNode {
	const pan = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => Math.abs(g.dx) > 10 && Math.abs(g.dx) > Math.abs(g.dy),
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => { log.push(`grant ${g.x0}`); },
		onPanResponderMove: (e: NeonEvent, g: PanResponderGestureState): void => { log.push(`move ${g.dx} ${g.vx}`); },
		onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => { log.push(`release ${g.dx}`); },
		onPanResponderTerminate: (e: NeonEvent, g: PanResponderGestureState): void => { log.push("terminate"); },
	});
	return element(<View {...pan.panHandlers} style={{ height: 40 }}><Text>row</Text></View>);
}

test "a horizontal pan claims on the move that crosses its slop and reads dx from the grant" {
	const log: string[] = [];
	const root = mount((): NeonNode => horizontalPan(log));
	const row = root.children[0];
	fireTouch(row.children[0], "onTouchStart", 100, 20, 1000);
	fireTouch(row.children[0], "onTouchMove", 105, 21, 1010);
	assert log.length === 0, "5px is under the slop: " + log.join(",");
	fireTouch(row.children[0], "onTouchMove", 120, 22, 1020);
	assert log.join(",") === "grant 120", "claimed at 120: " + log.join(",");
	assert row.holdsResponder && row.blocksNative, "the host is told the row holds the touch and blocks native scroll";
	fireTouch(row.children[0], "onTouchMove", 140, 22, 1030);
	assert log[1] === "move 20 2", "dx counts from the grant, 20 at 2 px/ms: " + log[1];
	fireTouch(row.children[0], "onTouchEnd", 140, 22, 1040);
	assert log[2] === "release 20", "release carries the last dx: " + log[2];
	assert !row.holdsResponder, "the host hears the touch ended";
}

test "a vertical drag over the row never claims" {
	const log: string[] = [];
	const root = mount((): NeonNode => horizontalPan(log));
	const row = root.children[0];
	fireTouch(row, "onTouchStart", 100, 20, 1);
	fireTouch(row, "onTouchMove", 102, 60, 2);
	fireTouch(row, "onTouchMove", 104, 100, 3);
	fireTouch(row, "onTouchEnd", 104, 100, 4);
	assert log.length === 0, "nothing granted: " + log.join(",");
}

test "a cancel from the host terminates the pan" {
	const log: string[] = [];
	const root = mount((): NeonNode => horizontalPan(log));
	const row = root.children[0];
	fireTouch(row, "onTouchStart", 100, 20, 1);
	fireTouch(row, "onTouchMove", 130, 20, 2);
	fireTouch(row, "onTouchCancel", 130, 20, 3);
	assert log[log.length - 1] === "terminate", "terminated: " + log.join(",");
}

test "a pan that claims on a move cancels the press of a Pressable inside it" {
	const log: string[] = [];
	const pan = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => Math.abs(g.dx) > 10,
	});
	const root = mount((): NeonNode => <View {...pan.panHandlers}>
		<Pressable onPressIn={(e: NeonEvent): void => { log.push("in"); }} onPressOut={(e: NeonEvent): void => { log.push("out"); }} onPress={(e: NeonEvent): void => { log.push("press"); }}><Text>open</Text></Pressable>
	</View>);
	const button = root.children[0].children[0];
	fireEvent(button, "onPointerDown");
	fireTouch(button, "onTouchStart", 10, 10, 1);
	fireTouch(button, "onTouchMove", 40, 10, 2);
	const up = neonEvent("pointerup");
	up.timeStamp = 3;
	fireTouch(button, "onTouchEnd", 40, 10, 3);
	fireEventWith(button, "onPointerUp", up);
	assert log.indexOf("press") < 0, "the swipe does not press: " + log.join(",");
	assert log[0] === "in", "the press began: " + log.join(",");
}

test "a plain tap through a pan row still presses" {
	const log: string[] = [];
	const pan = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => Math.abs(g.dx) > 10,
	});
	const root = mount((): NeonNode => <View {...pan.panHandlers}>
		<Pressable onPress={(e: NeonEvent): void => { log.push("press"); }}><Text>open</Text></Pressable>
	</View>);
	const button = root.children[0].children[0];
	fireTouch(button, "onTouchStart", 10, 10, 1);
	fireTouch(button, "onTouchMove", 12, 10, 2);
	fireTouch(button, "onTouchEnd", 12, 10, 3);
	const press = neonEvent("press");
	press.timeStamp = 3;
	fireEventWith(button, "onPress", press);
	assert log.join(",") === "press", "pressed: " + log.join(",");
}

test "the inner responder wins at start, an outer capture takes the touch on a move" {
	const log: string[] = [];
	const inner = PanResponder.create({
		onStartShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => true,
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => { log.push("inner grant"); },
		onPanResponderTerminate: (e: NeonEvent, g: PanResponderGestureState): void => { log.push("inner terminate"); },
	});
	const outer = PanResponder.create({
		onMoveShouldSetPanResponderCapture: (e: NeonEvent, g: PanResponderGestureState): boolean => Math.abs(g.dy) > 20,
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => { log.push("outer grant"); },
		onPanResponderMove: (e: NeonEvent, g: PanResponderGestureState): void => { log.push(`outer move ${g.dy}`); },
	});
	const root = mount((): NeonNode => <View {...outer.panHandlers}><View {...inner.panHandlers}><Text>x</Text></View></View>);
	const leaf = root.children[0].children[0];
	fireTouch(leaf, "onTouchStart", 0, 0, 1);
	assert log.join(",") === "inner grant", "deepest wins at start: " + log.join(",");
	fireTouch(leaf, "onTouchMove", 0, 10, 2);
	fireTouch(leaf, "onTouchMove", 0, 30, 3);
	assert log.join(",") === "inner grant,inner terminate,outer grant", "transfer: " + log.join(",");
	fireTouch(leaf, "onTouchMove", 0, 45, 4);
	assert log[3] === "outer move 15", "the new responder moves from its grant: " + log.join(",");
}

test "a responder that refuses termination keeps the touch" {
	const log: string[] = [];
	const inner = PanResponder.create({
		onStartShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => true,
		onPanResponderTerminationRequest: (e: NeonEvent, g: PanResponderGestureState): boolean => false,
	});
	const outer = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => true,
		onPanResponderReject: (e: NeonEvent, g: PanResponderGestureState): void => { log.push("rejected"); },
	});
	const root = mount((): NeonNode => <View {...outer.panHandlers}><View {...inner.panHandlers}><Text>x</Text></View></View>);
	const leaf = root.children[0].children[0];
	fireTouch(leaf, "onTouchStart", 0, 0, 1);
	fireTouch(leaf, "onTouchMove", 0, 10, 2);
	assert log.join(",") === "rejected", "outer is rejected: " + log.join(",");
	assert root.children[0].children[0].holdsResponder, "inner still holds";
}
