import { runApp, createNativeHost } from "../../src/platform/native/host";
import { render, Host, HostNode } from "../../src/render/host";
import { Pressable, ScrollView, ScrollViewHandle, View, ViewHandle } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { currentResponder, ResponderEntry } from "../../src/render/responder";
import { element } from "../../src/macros/ui/element";
import { sleepAsync } from "std/core/promise";
import {
	nmTouchFull, nmLastPressableTag, nmLastScrollTag, nmScroll, nmTeardown,
	nmTagWithProp, nmResponderBlocks, nmResponderTag,
} from "./nativeBridgeMock.h";

function observe(e: NeonEvent): void {}

test "native fresh acquisitions can start and end at the previous release timestamp" {
	let actual = "";
	for (const phase of [1, 3]) {
		let calls = "";
		runApp((): NeonNode => <View accessibilityLabel="equal-terminal-owner"
			onStartShouldSetResponder={(): boolean => true}
			onResponderEnd={(): void => { calls += "E"; }}
			onResponderRelease={(): void => { calls += "R"; }}
			onResponderTerminate={(): void => { calls += "C"; }}
			onTouchEnd={(): void => { calls += "raw"; }}
			onTouchCancel={(): void => { calls += "raw"; }} />);
		const source = nmTagWithProp("accessibilityLabel", "equal-terminal-owner");
		const stamp = 180000.0 + (phase as float64) * 1000.0;
		physical(source, 0, stamp - 20.0);
		physical(source, phase, stamp);
		physical(source, 0, stamp);
		physical(source, phase, stamp);
		actual += `${phase}:${calls}/${currentResponder() === null}|`;
		nmTeardown();
	}
	assert actual === "1:ERrawERraw/true|3:CrawCraw/true|", actual;
}

test "native unknown stale and duplicate terminal packets cannot retire a fresh responder" {
	let actual = "";
	let expected = "";
	for (const phase of [1, 3]) {
		for (const mode of [0, 1, 2]) {
			let calls = "";
			const hosts: Host[] = [];
			const stale: HostNode[] = [];
			runApp((): NeonNode => {
				const app = element(<View>
					<View accessibilityLabel="valid-terminal-owner"
						onStartShouldSetResponder={(): boolean => true}
						onResponderEnd={(): void => { calls += "E"; }}
						onResponderRelease={(): void => { calls += "R"; }}
						onResponderTerminate={(): void => { calls += "C"; }} />
					<View accessibilityLabel="stale-terminal-source" onLayout={observe}
						ref={(h: ViewHandle): void => { stale.push(h.node); }} />
				</View>);
				return (h: Host, p: HostNode, b: HostNode | null): void => {
					hosts.push(h); app(h, p, b);
				};
			});
			const source = nmTagWithProp("accessibilityLabel", "valid-terminal-owner");
			const staleTag = nmTagWithProp("accessibilityLabel", "stale-terminal-source");
			const parent = hosts[0].parentOf(stale[0]);
			if (parent === null) { throw "missing stale fixture parent"; }
			hosts[0].removeChild(parent as HostNode, stale[0]);
			const stamp = 170000.0 + (phase as float64) * 1000.0 + (mode as float64) * 100.0;
			physical(source, 0, stamp);
			if (mode === 2) {
				physical(source, phase, stamp + 20.0);
				calls = "";
				physical(source, phase, stamp + 20.0);
				assert calls === "", "a duplicate without a new acquisition emits no terminal callbacks";
				physical(source, 0, stamp + 30.0);
			}
			const holder = currentResponder();
			physical(mode === 0 ? 2000000000 : mode === 1 ? staleTag : source, phase, stamp + 20.0);
			actual += `${phase},${mode}:${calls}/${currentResponder() === holder && holder !== null}/${nmResponderBlocks()};`;
			expected += `${phase},${mode}:/true/0;`;
			physical(source, 1, stamp + 60.0);
			actual += calls + "|"; expected += "ER|";
			nmTeardown();
		}
	}
	assert actual === expected, actual;
}


test "native terminal captures release listener before End mutates responder handlers" {
	let actual = "";
	for (const restart of [false, true]) {
		let source: int32 = 0;
		const entries: ResponderEntry[] = [];
		runApp((): NeonNode => <View accessibilityLabel="captured-responder"
			onStartShouldSetResponder={(): boolean => true}
			onResponderEnd={(e: NeonEvent): void => {
				if (e.timeStamp !== 151020.0) { return; }
				actual += "end;";
				entries[0].handlers.onResponderRelease = (): void => { actual += "replacement;"; };
				if (restart) { physical(source, 0, 152000.0); }
			}}
			onResponderRelease={(e: NeonEvent): void => {
				if (e.timeStamp === 151020.0) { actual += "captured;"; }
			}} />);
		source = nmTagWithProp("accessibilityLabel", "captured-responder");
		physical(source, 0, 151000.0);
		entries.push(currentResponder() as ResponderEntry);
		physical(source, 1, 151020.0);
		if (restart) { entries[0].handlers.onResponderRelease = null; physical(source, 1, 152020.0); }
		nmTeardown();
	}
	assert actual === "end;captured;end;captured;", actual;
}

test "native custom End restart leaves the touch to the child Pressable, which RN asks first" {
	let actual = "";
	for (const restart of [false, true]) {
		let source: int32 = 0;
		let callbacks = "";
		runApp((): NeonNode => <View onStartShouldSetResponder={(): boolean => true}
			onResponderEnd={(e: NeonEvent): void => {
				if (e.timeStamp !== 153020.0) { return; }
				callbacks += "end;";
				if (restart) { physical(source, 0, 154000.0); }
			}}
			onResponderRelease={(e: NeonEvent): void => {
				if (e.timeStamp === 153020.0) { callbacks += "release;"; }
			}}>
			<Pressable onPressIn={observe} onPressOut={(): void => { callbacks += "out;"; }}
				onPress={(e: NeonEvent): void => { callbacks += `${e.timeStamp};`; }}>
				<View accessibilityLabel="end-restart-child" onLayout={observe} />
			</Pressable>
		</View>);
		source = nmTagWithProp("accessibilityLabel", "end-restart-child");
		physical(source, 0, 153000.0);
		await sleepAsync(150);
		physical(source, 1, 153020.0);
		if (restart) { physical(source, 1, 154020.0); }
		actual += `${restart}:${callbacks}|`;
		nmTeardown();
	}
	assert actual === "false:out;153020;|true:out;153020;|", actual;
}


function physical(tag: int32, phase: int32, stamp: float64): void {
	nmTouchFull(tag, phase, 10.0, 20.0, stamp);
}

function scroll(tag: int32): void {
	nmScroll(tag, 0.0, 20.0, 200.0, 100.0, 200.0, 500.0);
}

test "native scroll takes logical activation without cancelling raw touch or long feedback balance" {
	let result = "";
	for (const mode of [0, 1, 2]) {
		let hits = 0;
		let long = 0;
		let outs = 0;
		let starts = 0;
		let moves = 0;
		let ends = 0;
		let cancels = 0;
		runApp((): NeonNode => <View
			onTouchStart={(): void => { starts += 1; }}
			onTouchMove={(): void => { moves += 1; }}
			onTouchEnd={(): void => { ends += 1; }}
			onTouchCancel={(): void => { cancels += 1; }}>
			<ScrollView onScroll={observe}>
				<Pressable onPressIn={mode > 0 ? observe : null}
					onPressOut={mode > 0 ? (): void => { outs += 1; } : null}
					onLongPress={mode > 0 ? (): void => { long += 1; } : null}
					delayLongPress={25} onPress={(): void => { hits += 1; }} />
			</ScrollView>
		</View>);
		const source = nmLastPressableTag();
		const scroller = nmLastScrollTag();
		physical(source, 0, 40000.0);
		physical(source, 4, 40010.0);
		scroll(scroller);
		if (mode === 2) { await sleepAsync(90); }
		physical(source, 1, 40120.0);
		physical(source, 2, 40120.0);
		await sleepAsync(160);
		assert starts === 1 && moves === 1 && ends === 1 && cancels === 0;
		result += hits.toString() + "," + long.toString() + "," + outs.toString() + ";";
		nmTeardown();
	}
	assert result === "0,0,0;0,0,1;0,0,1;", result;
}

test "native scroll negotiates existing custom responder termination acceptance and refusal" {
	let result = "";
	for (const allowed of [false, true]) {
		let requested = 0;
		let terminated = 0;
		let released = 0;
		runApp((): NeonNode => <ScrollView onScroll={observe}>
			<View onStartShouldSetResponder={(): boolean => true}
				onResponderGrant={(): boolean => false}
				onResponderTerminationRequest={(): boolean => { requested += 1; return allowed; }}
				onResponderTerminate={(): void => { terminated += 1; }}
				onResponderRelease={(): void => { released += 1; }}>
				<View accessibilityLabel="termination-source" onLayout={observe} />
			</View>
		</ScrollView>);
		const source = nmTagWithProp("accessibilityLabel", "termination-source");
		physical(source, 0, 41000.0);
		scroll(nmLastScrollTag());
		physical(source, 1, 41020.0);
		result += requested.toString() + "," + terminated.toString() + "," + released.toString() + ";";
		nmTeardown();
	}
	assert result === "1,0,1;1,1,0;", result;
}

test "native scroll preserves a refusing native-blocking responder" {
	let terminated = 0;
	runApp((): NeonNode => <ScrollView onScroll={observe}>
		<View accessibilityLabel="scroll-blocker" onStartShouldSetResponder={(): boolean => true}
			onResponderGrant={(): boolean => true}
			onResponderTerminationRequest={(): boolean => false}
			onResponderTerminate={(): void => { terminated += 1; }} />
	</ScrollView>);
	const source = nmTagWithProp("accessibilityLabel", "scroll-blocker");
	physical(source, 0, 42000.0);
	assert nmResponderBlocks() === 1;
	scroll(nmLastScrollTag());
	assert nmResponderBlocks() === 1 && terminated === 0;
	physical(source, 1, 42020.0);
	assert nmResponderBlocks() === 0;
	nmTeardown();
}

test "native idle and unrelated scroll do not consume another physical acquisition" {
	let hits = 0;
	let scrolls = 0;
	runApp((): NeonNode => <View>
		<View onStartShouldSetResponder={(): boolean => true} onResponderGrant={(): boolean => false}>
			<Pressable accessibilityLabel="unrelated-scroll-press" onPressIn={observe}
				onPress={(): void => { hits += 1; }} />
		</View>
		<ScrollView onScroll={(): void => { scrolls += 1; }} />
	</View>);
	const source = nmLastPressableTag();
	const scroller = nmLastScrollTag();
	scroll(scroller);
	physical(source, 0, 43000.0);
	scroll(scroller);
	physical(source, 1, 43020.0);
	physical(source, 2, 43020.0);
	assert hits === 1 && scrolls === 2;
	nmTeardown();
}

test "native scroll transfer does not grant a disposed candidate after custom termination reentrancy" {
	let terminated = 0;
	runApp((): NeonNode => <ScrollView onScroll={observe}>
		<View accessibilityLabel="scroll-unmount-holder" onStartShouldSetResponder={(): boolean => true}
			onResponderGrant={(): boolean => false}
			onResponderTerminationRequest={(): boolean => true}
			onResponderTerminate={(): void => { terminated += 1; nmTeardown(); }} />
	</ScrollView>);
	const source = nmTagWithProp("accessibilityLabel", "scroll-unmount-holder");
	physical(source, 0, 44000.0);
	scroll(nmLastScrollTag());
	assert terminated === 1 && currentResponder() === null;
	physical(source, 1, 44020.0);
	physical(source, 2, 44020.0);
}

test "native scroll negotiation is present without user callbacks and bypasses user throttling" {
	for (const listening of [false, true]) {
		let hits = 0;
		let calls = 0;
		runApp((): NeonNode => <ScrollView
			onScroll={listening ? (): void => { calls += 1; } : null}
			scrollEventThrottle={100000000}>
			<Pressable onPressIn={observe} onPress={(): void => { hits += 1; }} />
		</ScrollView>);
		const source = nmLastPressableTag();
		const scroller = nmLastScrollTag();
		scroll(scroller);
		physical(source, 0, 45000.0);
		scroll(scroller);
		physical(source, 1, 45020.0);
		physical(source, 2, 45020.0);
		assert hits === 0 && calls === (listening ? 1 : 0);
		nmTeardown();
	}
}

test "native nested scroll keeps its accepted responder lock until raw end" {
	const native = createNativeHost();
	const handles: ScrollViewHandle[] = [];
	let hits = 0;
	const dispose = render(element(<ScrollView onScroll={observe}
		ref={(h: ScrollViewHandle): void => {
			handles.push(h);
			native.host.setAttr(h.node, "accessibilityLabel", "outer-scroll-responder");
		}}>
		<ScrollView onScroll={observe} ref={(h: ScrollViewHandle): void => {
			handles.push(h);
			native.host.setAttr(h.node, "accessibilityLabel", "inner-scroll-responder");
		}}>
			<Pressable onPress={(): void => { hits += 1; }} />
		</ScrollView>
	</ScrollView>), native.host, native.rootNode);
	const source = nmLastPressableTag();
	physical(source, 0, 46000.0);
	scroll(nmTagWithProp("accessibilityLabel", "inner-scroll-responder"));
	const inner = currentResponder();
	assert inner !== null && inner.node === handles[0].node;
	scroll(nmTagWithProp("accessibilityLabel", "outer-scroll-responder"));
	assert currentResponder() === inner, "observed inner scroll refuses ancestor transfer";
	physical(source, 1, 46020.0);
	physical(source, 2, 46020.0);
	assert hits === 0 && currentResponder() === null;
	dispose();
	native.host.removeChild(native.rootNode, handles[1].node);
}

test "native scroll termination request cannot grant across disposal or a new physical start" {
	for (const removing of [false, true]) {
		let source: int32 = 0;
		let requested = 0;
		let terminated = 0;
		runApp((): NeonNode => <ScrollView>
			<View accessibilityLabel="scroll-request-reentry" onStartShouldSetResponder={(): boolean => true}
				onResponderGrant={(): boolean => true}
				onResponderTerminationRequest={(): boolean => {
					requested += 1;
					if (removing) { nmTeardown(); } else {
						physical(source, 1, 50020.0);
						physical(source, 0, 51000.0);
					}
					return true;
				}}
				onResponderTerminate={(): void => { terminated += 1; }} />
		</ScrollView>);
		source = nmTagWithProp("accessibilityLabel", "scroll-request-reentry");
		physical(source, 0, 50000.0);
		const holder = currentResponder();
		scroll(nmLastScrollTag());
		assert requested === 1 && terminated === (removing ? 1 : 0);
		assert removing ? currentResponder() === null : currentResponder() === holder;
		assert nmResponderBlocks() === (removing ? 0 : 1);
		physical(source, 1, 51020.0);
		nmTeardown();
	}
}

test "native scroll pressOut reentrancy cannot apply an old grant after disposal or same-entry reacquisition" {
	for (const removing of [false, true]) {
		const native = createNativeHost();
		const original = native.host.setResponder;
		const handles: ScrollViewHandle[] = [];
		let grants = 0;
		native.host.setResponder = (node: HostNode | null, block: boolean): void => {
			if (node !== null && handles.length > 0 && node === handles[0].node) { grants += 1; }
			if (original !== null) { (original as (node: HostNode | null, block: boolean) => void)(node, block); }
		};
		let source: int32 = 0;
		let scroller: int32 = 0;
		let cleanup: (() => void) | null = null;
		let reentered = false;
		let outs = 0;
		let hits = 0;
		const base = removing ? 49000.0 : 47000.0;
		cleanup = render(element(<ScrollView ref={(h: ScrollViewHandle): void => { handles.push(h); }}>
			<Pressable onPress={(): void => { hits += 1; }} onPressOut={(): void => {
				outs += 1;
				if (reentered) { return; }
				reentered = true;
				if (removing) { (cleanup as () => void)(); } else {
					physical(source, 1, base + 20.0);
					physical(source, 2, base + 20.0);
					physical(source, 0, base + 1000.0);
					scroll(scroller);
				}
			}} />
		</ScrollView>), native.host, native.rootNode);
		source = nmLastPressableTag();
		scroller = nmLastScrollTag();
		physical(source, 0, base);
		await sleepAsync(150);
		scroll(scroller);
		const applied = grants;
		await sleepAsync(160);
		physical(source, 1, base + 1020.0);
		physical(source, 2, base + 1020.0);
		(cleanup as () => void)();
		native.host.removeChild(native.rootNode, handles[0].node);
		assert hits === 0 && outs === (removing ? 1 : 2);
		assert applied === (removing ? 0 : 1), `old/native scroll grants ${applied}`;
	}
}

test "native claim crossover contrasts sequential delivery with injected rawEnd restart" {
	let actual = "";
	let expected = "";
	for (const injected of [false, true]) {
		for (const sameStart of [false, true]) {
			for (const claimA of [false, true]) {
				let source: int32 = 0;
				let scroller: int32 = 0;
				let started = false;
				let delivering = "A";
				let stamps = "";
				const bStart = sameStart ? 94020.0 : 95000.0;
				const bEnd = bStart + 20.0;
				const beginB = (): void => {
					if (started) { return; }
					started = true;
					physical(source, 0, bStart);
					if (!claimA) { scroll(scroller); }
				};
				runApp((): NeonNode => <ScrollView>
					<Pressable onPress={(e: NeonEvent): void => { stamps += `${delivering}:${e.timeStamp};`; }}>
						<View accessibilityLabel="claim-crossover-source" onTouchEnd={(): void => {
							if (injected) { beginB(); }
						}} />
					</Pressable>
				</ScrollView>);
				source = nmTagWithProp("accessibilityLabel", "claim-crossover-source");
				scroller = nmLastScrollTag();
				physical(source, 0, 94000.0);
				if (claimA) { scroll(scroller); }
				physical(source, 1, 94020.0);
				physical(source, 2, 94020.0);
				if (!injected) { beginB(); }
				delivering = "B";
				physical(source, 1, bEnd);
				physical(source, 2, bEnd);
				actual += `${injected},${sameStart},${claimA}:${stamps}|`;
				expected += `${injected},${sameStart},${claimA}:` + (claimA ? `B:${bEnd};|` : "A:94020;|");
				nmTeardown();
			}
		}
	}
	assert actual === expected, actual;
}

test "native pure View clears old responder before terminal or disposal callbacks" {
	let actual = "";
	let expected = "";
	for (const mode of [0, 1, 2, 3]) {
		for (const restart of [false, true]) {
			for (const same of [false, true]) {
				const native = createNativeHost();
				let aTag: int32 = 0;
				let bTag: int32 = 0;
				let begun = false;
				let calls = "";
				const terminalStamp = mode === 3 ? 130000.0 : 130020.0;
				const bStart = same ? terminalStamp : 131000.0;
				const terminal = (which: int32, e: NeonEvent): void => {
					if (e.timeStamp !== terminalStamp) { return; }
					calls += which.toString();
					actual += `${which}:${nmResponderTag()},${nmResponderBlocks()},` +
						`${currentResponder() !== null};`;
					const owner = begun ? mode === 3 ? bTag : aTag : 0;
					expected += `${which}:${owner},${begun ? 1 : 0},${begun};`;
					if (!restart || which !== (mode === 3 ? 2 : mode)) { return; }
					begun = true;
					nmTouchFull(mode === 3 ? bTag : aTag, 0, 30.0, 40.0, bStart);
				};
				const disposeA = render(element(<View accessibilityLabel="release-order-A"
					onStartShouldSetResponder={(): boolean => true}
					onResponderGrant={(): boolean => true}
					onResponderEnd={(e: NeonEvent): void => { terminal(0, e); }}
					onResponderRelease={(e: NeonEvent): void => { terminal(1, e); }}
					onResponderTerminate={(e: NeonEvent): void => { terminal(2, e); }}
				/>), native.host, native.rootNode);
				const disposeB = render(element(<View accessibilityLabel="release-order-B"
					onStartShouldSetResponder={(): boolean => true}
					onResponderGrant={(): boolean => true}
				/>), native.host, native.rootNode);
				aTag = nmTagWithProp("accessibilityLabel", "release-order-A");
				bTag = nmTagWithProp("accessibilityLabel", "release-order-B");
				physical(aTag, 0, 130000.0);
				if (mode === 3) { disposeA(); }
				else { physical(aTag, mode === 2 ? 3 : 1, terminalStamp); }
				actual += `${mode},${restart},${same}:` +
					`${nmResponderTag()},${nmResponderBlocks()}/${calls}|`;
				const owner = restart ? mode === 3 ? bTag : aTag : 0;
				expected += `${mode},${restart},${same}:${owner},${restart ? 1 : 0}/` +
					(mode < 2 ? "01|" : "2|");
				if (restart) {
					nmTouchFull(mode === 3 ? bTag : aTag, 1, 30.0, 40.0, bStart + 20.0);
				}
				if (mode === 3 && !restart) {
					nmTouchFull(bTag, 0, 30.0, 40.0, terminalStamp + 50.0);
					nmTouchFull(bTag, 3, 30.0, 40.0, terminalStamp + 60.0);
				}
				if (mode !== 3) { disposeA(); }
				disposeB();
				nmTeardown();
			}
		}
	}
	assert actual === expected, actual;
}
