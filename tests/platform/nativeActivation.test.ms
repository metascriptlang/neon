import { runApp, createNativeHost } from "../../src/platform/native/host";
import "../../src/platform/native/switch";
import "../../src/platform/native/webView";
import "../../src/platform/native/video";
import "../../src/platform/native/camera";
import { Pressable, View, ViewHandle, Text, ScrollView } from "../../src/components/primitives";
import { Host, HostNode, render } from "../../src/render/host";
import { NeonNode, hostElement, attr } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { touchHistory } from "../../src/render/responder";
import { createSignal } from "../../src/core/signal";
import { Show } from "../../src/macros/ui/flow";
import { element } from "../../src/macros/ui/element";
import { sleepAsync } from "std/core/promise";
import {
	nmTouchFull, nmLastPressableTag, nmLastViewTag, nmLastInputTag, nmLastControlTag, nmLastScrollTag, nmScroll,
	nmTagWithProp, nmProp, nmTeardown, nmLoop,
} from "./nativeBridgeMock.h";

function feedback(e: NeonEvent): void {}

test "native phased ordinary registrations keep layout and press node readiness" {
	let log = "";
	runApp((): NeonNode => hostElement("view", [attr("accessibilityLabel", "phased-node")], [
		{ name: "onLayout", lifecycle: (e: NeonEvent): void => { log += `layout-life:${e.width};`; },
			handler: (e: NeonEvent): void => { log += `layout-user:${e.width};`; } },
		{ name: "onPress", lifecycle: (): void => { log += "press-life;"; },
			handler: (): void => { log += "press-user;"; } },
	], null, (): Style => ({ width: 20, height: 30 }), null));
	const source = nmTagWithProp("accessibilityLabel", "phased-node");
	physical(source, 0, 190000.0);
	physical(source, 1, 190020.0);
	physical(source, 2, 190020.0);
	nmTeardown();
	assert log === "layout-life:20;layout-user:20;press-life;press-user;", log;
}

test "native terminal groups precede raw observers and capture later listeners before mutation" {
	let actual = "";
	let expected = "";
	for (const phase of [1, 3]) {
		for (const remove of [false, true]) {
			const hosts: Host[] = [];
			const roots: HostNode[] = [];
			const wrappers: ViewHandle[] = [];
			let log = "";
			let changed = false;
			runApp((): NeonNode => {
			const app = element(<View ref={(h: ViewHandle): void => { wrappers.push(h); }}
				onStartShouldSetResponder={(): boolean => true}
				onResponderEnd={(): void => { log += "end;"; }}
				onResponderRelease={(): void => { log += "release;"; }}
				onResponderTerminate={(): void => { log += "terminate;"; }}
				onTouchEnd={(): void => { log += "ancestor;"; }}
				onTouchCancel={(): void => { log += "ancestor;"; }}>
				<Pressable onPressIn={feedback} onPressOut={(): void => { log += "out;"; }}
					onPress={(): void => { log += "press;"; }}>
					<View accessibilityLabel="phase-capture-leaf"
						onTouchEnd={(): void => {
							log += "raw;";
							if (changed) { return; } changed = true;
							if (remove) { hosts[0].removeChild(roots[0], wrappers[0].node); }
							else { hosts[0].addEvent(wrappers[0].node, "onTouchEnd", (): void => { log += "new;"; }); }
						}}
						onTouchCancel={(): void => {
							log += "raw;";
							if (changed) { return; } changed = true;
							if (remove) { hosts[0].removeChild(roots[0], wrappers[0].node); }
							else { hosts[0].addEvent(wrappers[0].node, "onTouchCancel", (): void => { log += "new;"; }); }
						}} />
				</Pressable>
			</View>);
			return (h: Host, p: HostNode, b: HostNode | null): void => {
				hosts.push(h); roots.push(p); app(h, p, b);
			};
			});
			const source = nmTagWithProp("accessibilityLabel", "phase-capture-leaf");
			const stamp = 150000.0 + (phase as float64) * 1000.0 + (remove ? 100.0 : 0.0);
			physical(source, 0, stamp);
			await sleepAsync(150);
			physical(source, phase, stamp + 20.0);
			actual += `${phase},${remove}:${log}|`;
			expected += `${phase},${remove}:` + (phase === 1 ? "end;release;out;press;" : "terminate;out;") + "raw;ancestor;|";
			nmTeardown();
		}
	}
	assert actual === expected, actual;
}


function historyActive(): int32 { return touchHistory().numberActiveTouches; }

function physical(tag: int32, phase: int32, stamp: float64): void {
	nmTouchFull(tag, phase, 5.0, 5.0, stamp);
}

test "native activation crosses generic layout and touch descendants but raw touch still bubbles once" {
	let result = "";
	for (const gesture of [false, true]) {
		for (const observe of [false, true]) {
			let hits = 0;
			let parentTouches = 0;
			let childTouches = 0;
			runApp((): NeonNode => <View onTouchStart={(): void => { parentTouches += 1; }}>
				<Pressable onPressIn={gesture ? feedback : null}
					onPress={(): void => { hits += 1; }}>
					{observe
						? element(<View accessibilityLabel="activation-leaf"
							onTouchStart={(): void => { childTouches += 1; }} />)
						: element(<View accessibilityLabel="activation-leaf" onLayout={feedback} />)}
				</Pressable>
			</View>);
			const leaf = nmTagWithProp("accessibilityLabel", "activation-leaf");
			assert leaf !== 0;
			physical(leaf, 0, 30000.0);
			physical(leaf, 1, 30020.0);
			physical(leaf, 2, 30020.0);
			assert parentTouches === 1 && childTouches === (observe ? 1 : 0);
			result += hits.toString() + ";";
			nmTeardown();
		}
	}
	assert result === "1;1;1;1;", result;
}

test "native desktop chain retains nearest owner across cheap and gesture tiers" {
	let result = "";
	for (const parentGesture of [false, true]) {
		for (const childGesture of [false, true]) {
			let inner = 0;
			let outer = 0;
			runApp((): NeonNode => <Pressable accessibilityLabel="activation-parent"
				onPressIn={parentGesture ? feedback : null}
				onPress={(): void => { outer += 1; }}>
				<Pressable accessibilityLabel="activation-child"
					onPressIn={childGesture ? feedback : null}
					onPress={(): void => { inner += 1; }} />
			</Pressable>);
			const child = nmLastPressableTag();
			const parent = nmTagWithProp("accessibilityLabel", "activation-parent");
			physical(child, 0, 31000.0);
			physical(parent, 0, 31000.0);
			physical(child, 1, 31020.0);
			physical(child, 2, 31020.0);
			physical(parent, 1, 31020.0);
			physical(parent, 2, 31020.0);
			result += inner.toString() + "," + outer.toString() + ";";
			nmTeardown();
		}
	}
	assert result === "1,0;1,0;1,0;1,0;", result;
}

test "native passive Pressable is an activation boundary without adding listeners" {
	const native = createNativeHost();
	const add = native.host.addEvent;
	let listeners = 0;
	native.host.addEvent = (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
		listeners += 1;
		add(node, name, handler);
	};
	const parent = native.host.createElement("pressable");
	let outer = 0;
	native.host.addEvent(parent, "onPress", (): void => { outer += 1; });
	const parentTag = nmLastViewTag();
	const passive = native.host.createElement("pressable");
	const tag = nmLastViewTag();
	assert listeners === 1, "only the declared parent callback is registered";
	assert tag !== 0 && tag !== parentTag, "callback-less owner needs its own reported tag";
	native.host.setAttr(passive, "accessibilityLabel", "activation-passive");
	native.host.append(parent, passive);
	native.host.append(native.rootNode, parent);
	assert tag === nmTagWithProp("accessibilityLabel", "activation-passive");
	physical(tag, 0, 32000.0);
	physical(tag, 1, 32020.0);
	physical(tag, 2, 32020.0);
	assert outer === 0;
	native.host.removeChild(native.rootNode, parent);
}

test "native callback-less Input Switch and interactive Media stop ancestor activation" {
	for (const kind of ["textinput", "switch", "webview", "video", "camera"]) {
		const native = createNativeHost();
		const parent = native.host.createElement("pressable");
		let hits = 0;
		native.host.addEvent(parent, "onPress", (): void => { hits += 1; });
		const parentTag = nmLastViewTag();
		const barrier = native.host.createElement(kind);
		native.host.setAttr(barrier, "accessibilityLabel", "activation-barrier");
		const tag = nmTagWithProp("accessibilityLabel", "activation-barrier");
		assert tag !== 0 && tag !== parentTag, "native barrier has its own tag: " + kind;
		const controlKind: int32 = match (kind) {
			"switch" => 2,
			"webview" => 10,
			"video" => 11,
			"camera" => 12,
			_ => 1,
		};
		assert tag === (kind === "textinput" ? nmLastInputTag() : nmLastControlTag(controlKind));
		native.host.append(parent, barrier);
		native.host.append(native.rootNode, parent);
		physical(tag, 0, 33000.0);
		physical(tag, 1, 33020.0);
		physical(tag, 2, 33020.0);
		assert hits === 0, kind;
		native.host.removeChild(native.rootNode, parent);
	}
}

test "native activation retains cheap and gesture owners when only their generic source is removed" {
	let result = "";
	for (const gesture of [false, true]) {
		const [visible, setVisible] = createSignal(true);
		let hits = 0;
		runApp((): NeonNode => <Pressable onPressIn={gesture ? feedback : null}
			onPress={(): void => { hits += 1; }}>
			<Show when={visible()}>
				<View accessibilityLabel="activation-removed-leaf" onLayout={feedback} />
			</Show>
		</Pressable>);
		const source = nmTagWithProp("accessibilityLabel", "activation-removed-leaf");
		physical(source, 0, 34000.0);
		setVisible(false);
		nmLoop();
		physical(source, 1, 34020.0);
		physical(source, 2, 34020.0);
		result += hits.toString() + ";";
		nmTeardown();
	}
	assert result === "1;1;", result;
}

test "native raw end removal vetoes late cheap activation but not earlier gesture activation" {
	let result = "";
	for (const removeOwner of [false, true]) {
		for (const gesture of [false, true]) {
			const native = createNativeHost();
			const leaves: ViewHandle[] = [];
			const wrappers: ViewHandle[] = [];
			let hits = 0;
			let rawEnds = 0;
			const dispose = render(element(<View
				ref={(h: ViewHandle): void => { wrappers.push(h); }}
				onTouchEnd={(): void => { rawEnds += 1; }}>
				<Pressable onPressIn={gesture ? feedback : null}
					onPress={(): void => { hits += 1; }}>
					<View accessibilityLabel="activation-end-leaf"
						ref={(h: ViewHandle): void => { leaves.push(h); }}
						onTouchEnd={(): void => {
							const leaf = leaves[0].node;
							const owner = native.host.parentOf(leaf);
							if (owner === null) { return; }
							if (removeOwner) {
								const parent = native.host.parentOf(owner);
								if (parent !== null) { native.host.removeChild(parent, owner); }
							} else { native.host.removeChild(owner, leaf); }
						}} />
				</Pressable>
			</View>), native.host, native.rootNode);
			const source = nmTagWithProp("accessibilityLabel", "activation-end-leaf");
			physical(source, 0, 34500.0);
			physical(source, 1, 34520.0);
			physical(source, 2, 34520.0);
			result += hits.toString() + "," + rawEnds.toString() + ";";
			dispose();
			native.host.removeChild(native.rootNode, wrappers[0].node);
		}
	}
	assert result === "1,1;1,1;0,1;1,1;", result;
}

test "native stale release after teardown cannot consume a remounted acquisition" {
	let hits = 0;
	const app = (): NeonNode => <Pressable onPressIn={feedback}
		onPress={(): void => { hits += 1; }} />;
	runApp(app);
	const old = nmLastPressableTag();
	physical(old, 0, 35000.0);
	nmTeardown();
	runApp(app);
	const fresh = nmLastPressableTag();
	assert fresh !== old;
	physical(fresh, 0, 35010.0);
	physical(old, 1, 35020.0);
	physical(old, 2, 35020.0);
	physical(fresh, 1, 35030.0);
	physical(fresh, 2, 35030.0);
	assert hits === 1;
	nmTeardown();
}

test "native long-only child owns acquisition through a generic descendant" {
	let child = 0;
	let parent = 0;
	runApp((): NeonNode => <Pressable onPress={(): void => { parent += 1; }}>
		<Pressable delayLongPress={25} onLongPress={(): void => { child += 1; }}>
			<View accessibilityLabel="activation-long-leaf" onLayout={feedback} />
		</Pressable>
	</Pressable>);
	const source = nmTagWithProp("accessibilityLabel", "activation-long-leaf");
	physical(source, 0, 36000.0);
	await sleepAsync(90);
	physical(source, 1, 36100.0);
	physical(source, 2, 36100.0);
	assert child === 1 && parent === 0;
	nmTeardown();
}

test "native exact span owner is distinct from plain run container and ancestor ownership" {
	for (const containerPress of [false, true]) {
		let spanHits = 0;
		let textHits = 0;
		let parentHits = 0;
		const textPress = (e: NeonEvent): void => { textHits += 1; };
		runApp((): NeonNode => <Pressable accessibilityLabel="activation-span-parent"
			onPress={(): void => { parentHits += 1; }}>
			<Text accessibilityLabel="activation-span-label"
				onPress={containerPress ? textPress : null}
				spans={[{ text: "link", onPress: (): void => { spanHits += 1; } }, { text: " plain" }]} />
		</Pressable>);
		const parent = nmTagWithProp("accessibilityLabel", "activation-span-parent");
		const label = nmTagWithProp("accessibilityLabel", "activation-span-label");
		const encoded = nmProp(label, "textSpans");
		const fields = encoded.split("\u001e")[0].split("\u001f");
		const span = parseInt(fields[7]) as int32;
		assert span !== 0 && span !== label;
		physical(span, 0, 37000.0);
		physical(label, 0, 37000.0);
		physical(parent, 0, 37000.0);
		physical(span, 1, 37020.0);
		physical(span, 2, 37020.0);
		physical(label, 1, 37020.0);
		physical(label, 2, 37020.0);
		physical(parent, 1, 37020.0);
		physical(parent, 2, 37020.0);
		assert spanHits === 1 && textHits === 0 && parentHits === 0;
		physical(label, 0, 37100.0);
		physical(label, 1, 37120.0);
		physical(label, 2, 37120.0);
		assert spanHits === 1 && textHits === (containerPress ? 1 : 0);
		assert parentHits === (containerPress ? 0 : 1), "hit-test readiness is not whole-Text ownership";
		nmTeardown();
	}
}

test "native raw terminal reentry preserves fresh same-owner short activation and raw scroll ancestry" {
	let result = "";
	for (const terminal of [1, 3]) {
		for (const gesture of [false, true]) {
			let source: int32 = 0;
			let restarted = false;
			let stamps = "";
			let ins = 0;
			let outs = 0;
			let starts = 0;
			let ends = 0;
			let cancels = 0;
			let settled = false;
			let boundary = "";
			const restart = (e: NeonEvent): void => {
				if (restarted) { return; }
				boundary = settled ? "done" : "pending";
				restarted = true;
				physical(source, 0, 71000.0);
			};
			runApp((): NeonNode => <View
				onTouchStart={(): void => { starts += 1; }}
				onTouchEnd={(): void => { ends += 1; }}
				onTouchCancel={(): void => { cancels += 1; }}>
				<ScrollView><Pressable
					onPressIn={gesture ? (): void => { ins += 1; } : null}
					onPressOut={gesture ? (e: NeonEvent): void => {
						outs += 1;
						if (e.timeStamp === 70020.0) { settled = true; }
					} : null}
					onPress={(e: NeonEvent): void => { stamps += `${e.timeStamp};`; }}>
					<View accessibilityLabel="terminal-reentry-source"
						onTouchEnd={terminal === 1 ? restart : null}
						onTouchCancel={terminal === 3 ? restart : null} />
				</Pressable></ScrollView>
			</View>);
			source = nmTagWithProp("accessibilityLabel", "terminal-reentry-source");
			physical(source, 0, 70000.0);
			await sleepAsync(150);
			physical(source, terminal, 70020.0);
			const active = historyActive();
			physical(source, 2, 70020.0);
			physical(source, 1, 71020.0);
			physical(source, 2, 71020.0);
			await sleepAsync(160);
			result += `${terminal},${gesture}:${stamps}/${ins},${outs}/${active}/${starts},${ends},${cancels}/${boundary}|`;
			nmTeardown();
		}
	}
	assert result === "1,false:70020;71020;/0,0/1/2,2,0/pending|1,true:70020;71020;/2,2/1/2,2,0/done|3,false:71020;/0,0/1/2,1,1/pending|3,true:71020;/2,2/1/2,1,1/done|", result;
}

test "native raw cancel and end reentry give fresh long gesture its own timer and feedback" {
	let result = "";
	for (const terminal of [1, 3]) {
		let source: int32 = 0;
		let restarted = false;
		let longs = "";
		let hits = 0;
		let ins = 0;
		let outs = 0;
		const restart = (e: NeonEvent): void => {
			if (restarted) { return; }
			restarted = true;
			physical(source, 0, 73000.0);
		};
		runApp((): NeonNode => <ScrollView><Pressable delayLongPress={25}
			onPressIn={(): void => { ins += 1; }} onPressOut={(): void => { outs += 1; }}
			onPress={(): void => { hits += 1; }}
			onLongPress={(e: NeonEvent): void => { longs += `${e.timeStamp};`; }}>
			<View accessibilityLabel="terminal-reentry-long"
				onTouchEnd={terminal === 1 ? restart : null}
				onTouchCancel={terminal === 3 ? restart : null} />
		</Pressable></ScrollView>);
		source = nmTagWithProp("accessibilityLabel", "terminal-reentry-long");
		physical(source, 0, 72000.0);
		await sleepAsync(150);
		physical(source, terminal, 72020.0);
		physical(source, 2, 72020.0);
		await sleepAsync(150);
		physical(source, 1, 73020.0);
		physical(source, 2, 73020.0);
		await sleepAsync(30);
		result += `${terminal}:${longs}/${hits}/${ins},${outs}|`;
		nmTeardown();
	}
	assert result === "1:72000;73000;/0/2,2|3:72000;73000;/0/2,2|", result;
}

test "native gesture onPressOut restart cannot borrow fresh scroll claim for old activation" {
	let actual = "";
	let expected = "";
	for (const restart of [false, true]) {
		for (const sameStart of [false, true]) {
			let source: int32 = 0;
			let scroller: int32 = 0;
			let restarted = false;
			let ins = 0;
			let outs = 0;
			let stamps = "";
			const bStart = sameStart ? 96020.0 : 97000.0;
			runApp((): NeonNode => <ScrollView><Pressable
				onPressIn={(): void => { ins += 1; }}
				onPressOut={(): void => {
					outs += 1;
					if (!restart || restarted) { return; }
					restarted = true;
					physical(source, 0, bStart);
					nmScroll(scroller, 0.0, 20.0, 200.0, 100.0, 200.0, 500.0);
				}}
				onPress={(e: NeonEvent): void => { stamps += `${e.timeStamp};`; }}>
				<View accessibilityLabel="out-restart-claim" onLayout={feedback} />
			</Pressable></ScrollView>);
			source = nmTagWithProp("accessibilityLabel", "out-restart-claim");
			scroller = nmLastScrollTag();
			physical(source, 0, 96000.0);
			await sleepAsync(150);
			physical(source, 1, 96020.0);
			physical(source, 2, 96020.0);
			if (restart) {
				physical(source, 1, bStart + 20.0);
				physical(source, 2, bStart + 20.0);
			}
			await sleepAsync(160);
			actual += `${restart},${sameStart}:${stamps}/${ins},${outs}|`;
			expected += `${restart},${sameStart}:96020;/` + (restart ? "2,2|" : "1,1|");
			nmTeardown();
		}
	}
	assert actual === expected, actual;
}

test "native onPress restart gives fresh minimum feedback its own timer" {
	let actual = "";
	let expected = "";
	let timerOwner = true;
	let validWindow = true;
	let timing = "";
	for (const restart of [false, true]) {
		let source: int32 = 0;
		let restarted = false;
		let ins = 0;
		let outs = 0;
		let bStartedAt = -1.0;
		let outAt = -1.0;
		let stamps = "";
		runApp((): NeonNode => <Pressable onPressIn={(): void => { ins += 1; }}
			onPressOut={(): void => { outs += 1; outAt = performance.now(); }}
			onPress={(e: NeonEvent): void => {
				stamps += `${e.timeStamp};`;
				if (!restart || restarted) { return; }
				restarted = true;
				bStartedAt = performance.now();
				physical(source, 0, 99000.0);
			}}><View accessibilityLabel="press-restart-timer" onLayout={feedback} /></Pressable>);
		source = nmTagWithProp("accessibilityLabel", "press-restart-timer");
		const began = performance.now();
		physical(source, 0, 98000.0);
		await sleepAsync(80);
		const age = performance.now() - began;
		validWindow = validWindow && age < 120;
		physical(source, 1, 98020.0);
		physical(source, 2, 98020.0);
		if (restart) {
			physical(source, 1, 99020.0);
			physical(source, 2, 99020.0);
		}
		await sleepAsync(180);
		if (restart) { timerOwner = timerOwner && outAt - bStartedAt >= 125; }
		timing += `${restart}:Aage${age},BoutAge${outAt - bStartedAt};`;
		actual += `${restart}:${stamps}/${ins},${outs}|`;
		expected += restart ? "true:98020;99020;/2,1|" : "false:98020;/1,1|";
		nmTeardown();
	}
	assert validWindow, "timing setup window lost: " + timing;
	assert actual === expected && timerOwner, actual + " " + timing;
}
