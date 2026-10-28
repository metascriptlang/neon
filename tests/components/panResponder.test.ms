import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent, fireEventWith, fireTouch } from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { View, Pressable, Text } from "../../src/components/primitives";
import { PanResponder, PanResponderGestureState } from "../../src/components/panResponder";
import { currentResponder, touchHistory } from "../../src/render/responder";

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
	const duplicate = neonEvent("press");
	duplicate.pointerOrigin = true;
	duplicate.timeStamp = 3;
	fireEventWith(button, "onPress", duplicate);
	assert log.indexOf("press") < 0, "the swipe does not press: " + log.join(",");
	assert log[0] === "in", "the press began: " + log.join(",");
	fireEventWith(button, "onPress", neonEvent("press"));
	assert log[log.length - 1] === "press", "later semantic activation remains independent";
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
	press.pointerOrigin = true;
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

test "cheap Pressable filters only pointer-origin activation after a claimed drag" {
	let hits = 0;
	const pan = PanResponder.create({
		onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean =>
			Math.abs(g.dx) > 10,
	});
	const root = mount((): NeonNode => <View {...pan.panHandlers}>
		<Pressable onPress={(): void => { hits += 1; }} />
	</View>);
	const button = root.children[0].children[0];
	fireTouch(button, "onTouchStart", 10, 10, 100);
	fireTouch(button, "onTouchMove", 40, 10, 110);
	const press = neonEvent("press");
	press.pointerOrigin = true;
	press.timeStamp = 120;
	fireEventWith(button, "onPress", press);
	assert hits === 0, "active claim suppresses physical press";
	const semantic = neonEvent("press");
	semantic.timeStamp = 120;
	fireEventWith(button, "onPress", semantic);
	assert hits === 1, "active claim does not suppress semantic activation";
	fireTouch(button, "onTouchEnd", 40, 10, 120);
	fireEventWith(button, "onPress", press);
	assert hits === 1, "claimed release suppresses physical duplicate";
	fireEventWith(button, "onPress", semantic);
	assert hits === 2, "identical timestamp does not make semantic activation physical";
}

test "public mock Pan terminal reentry keeps state identity and ownership while the trailing reset clears geometry as RN" {
	let actual = "";
	let expected = "";
	let oldData = "";
	for (const mode of [0, 1, 2]) {
		for (const restart of [false, true]) {
			for (const same of [false, true]) {
				const root = mockNode("root");
				let row: MockNode | null = null;
				let restarted = false;
				const states: PanResponderGestureState[] = [];
				const bStart = same ? 90020 : 91000;
				const terminal = (which: int32, e: NeonEvent, g: PanResponderGestureState): void => {
					if (e.timeStamp === 90020) {
						oldData += `${mode},${which}:${e.x},${e.y}/${g.x0},${g.y0}/${g === states[0]};`;
						assert e.x === 10 && e.y === 20 && g === states[0], oldData;
					}
					if (!restart || restarted || which !== mode) { return; }
					restarted = true;
					fireTouch(row as MockNode, "onTouchStart", 30, 40, bStart);
				};
				const pan = PanResponder.create({
					onStartShouldSetPanResponder: (): boolean => true,
					onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => { states.push(g); },
					onPanResponderEnd: (e: NeonEvent, g: PanResponderGestureState): void => { terminal(0, e, g); },
					onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => { terminal(1, e, g); },
					onPanResponderTerminate: (e: NeonEvent, g: PanResponderGestureState): void => { terminal(2, e, g); },
				});
				const dispose = render(element(<View {...pan.panHandlers} />), mockHost(), root as unknown as HostNode);
				row = root.children[0];
				fireTouch(row as MockNode, "onTouchStart", 10, 20, 90000);
				const entry = currentResponder();
				fireTouch(row as MockNode, mode === 2 ? "onTouchCancel" : "onTouchEnd", 10, 20, 90020);
				const g = states[0];
				const node = row as MockNode;
				actual += `${mode},${restart},${same}:${g.x0},${g.y0},${g.numberActiveTouches}/${touchHistory().numberActiveTouches}/${node.holdsResponder && node.blocksNative}/`;
				expected += `${mode},${restart},${same}:` + (restart ? "0,0,0/1/true/" : "0,0,0/0/false/");
				if (restart) {
					assert states.length === 2 && states[1] === g && currentResponder() === entry;
					fireTouch(node, "onTouchMove", 35, 45, bStart + 10);
					actual += `${g.x0},${g.y0},${g.dx},${g.dy},${g.numberActiveTouches};`;
					expected += "0,0,5,5,1;";
					fireTouch(node, "onTouchEnd", 35, 45, bStart + 20);
				} else { actual += "idle;"; expected += "idle;"; }
				dispose();
			}
		}
	}
	assert actual === expected, actual + " old callbacks: " + oldData;
}

test "public mock Pan release throw after fresh start does not run old trailing reset" {
	const root = mockNode("root");
	let row: MockNode | null = null;
	let restarted = false;
	const states: PanResponderGestureState[] = [];
	const pan = PanResponder.create({
		onStartShouldSetPanResponder: (): boolean => true,
		onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => { states.push(g); },
		onPanResponderRelease: (): void => {
			if (restarted) { return; }
			restarted = true;
			fireTouch(row as MockNode, "onTouchStart", 30, 40, 92020);
			throw "terminal throw";
		},
	});
	const dispose = render(element(<View {...pan.panHandlers} />), mockHost(), root as unknown as HostNode);
	row = root.children[0];
	fireTouch(row as MockNode, "onTouchStart", 10, 20, 92000);
	let error = "";
	try { fireTouch(row as MockNode, "onTouchEnd", 10, 20, 92020); } catch (e) { error = e.toString(); }
	const node = row as MockNode;
	const g = states[0];
	const survived = states.length === 2 && states[1] === g && node.holdsResponder && node.blocksNative &&
		g.x0 === 30 && g.y0 === 40 && touchHistory().numberActiveTouches === 1;
	fireTouch(node, "onTouchEnd", 30, 40, 92040);
	dispose();
	assert error.includes("terminal throw") && survived, error;
}

test "pure View terminal callbacks retire old native ownership before reentry or throw" {
	let actual = "";
	let expected = "";
	for (const mode of [0, 1, 2]) {
		for (const restart of [false, true]) {
			for (const same of [false, true]) {
				for (const throwing of [false, true]) {
					const root = mockNode("root");
					let row: MockNode | null = null;
					let begun = false;
					let calls = "";
					const bStart = same ? 110020 : 111000;
					const terminal = (which: int32, e: NeonEvent): void => {
						if (e.timeStamp !== 110020) { return; }
						calls += which.toString();
						const n = row as MockNode;
						actual += `${which}:${n.holdsResponder},${n.blocksNative},` +
							`${currentResponder() !== null};`;
						expected += `${which}:${begun},${begun},${begun};`;
						if (which !== mode) { return; }
						if (restart) {
							begun = true;
							fireTouch(n, "onTouchStart", 30, 40, bStart);
						}
						if (throwing) { throw "pure terminal throw"; }
					};
					const dispose = render(element(<View
						onStartShouldSetResponder={(): boolean => true}
						onResponderGrant={(): boolean => true}
						onResponderEnd={(e: NeonEvent): void => { terminal(0, e); }}
						onResponderRelease={(e: NeonEvent): void => { terminal(1, e); }}
						onResponderTerminate={(e: NeonEvent): void => { terminal(2, e); }}
					/>), mockHost(), root as unknown as HostNode);
					row = root.children[0];
					fireTouch(row as MockNode, "onTouchStart", 10, 20, 110000);
					let error = "";
					try {
						fireTouch(row as MockNode, mode === 2 ? "onTouchCancel" : "onTouchEnd",
							10, 20, 110020);
					} catch (e) { error = e.toString(); }
					const n = row as MockNode;
					actual += `${mode},${restart},${same},${throwing}:` +
						`${n.holdsResponder},${n.blocksNative}/${calls}|`;
					const order = mode === 2 ? "2" : throwing && mode === 0 ? "0" : "01";
					expected += `${mode},${restart},${same},${throwing}:` +
						`${restart},${restart}/${order}|`;
					if (restart) { fireTouch(n, "onTouchEnd", 30, 40, bStart + 20); }
					dispose();
					assert throwing ? error.includes("pure terminal throw") : error === "", error;
				}
			}
		}
	}
	assert actual === expected, actual;
}

test "pure View disposal releases native ownership before terminate callback starts another root" {
	let actual = "";
	let expected = "";
	for (const restart of [false, true]) {
		for (const same of [false, true]) {
			for (const throwing of [false, true]) {
				const root = mockNode("root");
				const host = mockHost();
				let a: MockNode | null = null;
				let b: MockNode | null = null;
				let calls = 0;
				const bStart = same ? 120000 : 121000;
				const disposeA = render(element(<View
					onStartShouldSetResponder={(): boolean => true}
					onResponderGrant={(): boolean => true}
					onResponderTerminate={(): void => {
						calls += 1;
						actual += `${(a as MockNode).holdsResponder},` +
							`${(a as MockNode).blocksNative}/${currentResponder() !== null};`;
						expected += "false,false/false;";
						if (restart) {
							fireTouch(b as MockNode, "onTouchStart", 30, 40, bStart);
						}
						if (throwing) { throw "unmount terminal throw"; }
					}}
				/>), host, root as unknown as HostNode);
				const disposeB = render(element(<View
					onStartShouldSetResponder={(): boolean => true}
					onResponderGrant={(): boolean => true}
				/>), host, root as unknown as HostNode);
				a = root.children[0]; b = root.children[1];
				fireTouch(a as MockNode, "onTouchStart", 10, 20, 120000);
				let error = "";
				try { disposeA(); } catch (e) { error = e.toString(); }
				actual += `${restart},${same},${throwing}:` +
					`${(b as MockNode).holdsResponder},${(b as MockNode).blocksNative}/${calls}|`;
				expected += `${restart},${same},${throwing}:${restart},${restart}/1|`;
				if (restart) { fireTouch(b as MockNode, "onTouchEnd", 30, 40, bStart + 20); }
				else { fireTouch(a as MockNode, "onTouchCancel", 10, 20, 120020); }
				disposeB();
				assert throwing ? error.includes("unmount terminal throw") : error === "", error;
			}
		}
	}
	assert actual === expected, actual;
}
