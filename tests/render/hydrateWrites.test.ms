import { NeonNode, el, text } from "../../src/render/node";
import { Host } from "../../src/render/hostTypes";
import { Loading } from "../../src/macros/ui/flow";
import { Computation, Cleanup } from "../../src/core/types";
import { createSignal, Accessor, Setter, accessor } from "../../src/core/signal";
import { createMemo, createAsyncMemo } from "../../src/core/memo";
import { onSettled, createEffect, createRenderEffect } from "../../src/core/effect";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { createStore } from "../../src/core/store";
import { render, mockHost, mockNode, mockToString, MockNode, HostNode } from "../../src/render/host";
import { hydrate } from "../../src/render/hydrate";
import { hydrating } from "../../src/render/claim";
import { lazyModule } from "../../src/render/lazy";
import { putModule, clearRecords } from "../../src/render/hydrationRecords";
import { View, Text } from "../../src/components/primitives";
import { flush, resetErrorHalt, getOwner } from "../../src/core/runtime";
import { markSnapshotScope } from "../../src/core/snapshotScope";
import { Gate, gated, release } from "../core/asyncClock";

function served(tree: NeonNode): MockNode {
	const root = mockNode("root");
	const dispose = render(tree, mockHost(), root as unknown as HostNode, "");
	dispose();
	return root;
}

function Header(props: { checked: Accessor<boolean> }): NeonNode {
	return <Show when={props.checked()} fallback={<Text>sign in</Text>}><Text>me</Text></Show>;
}

const ON_SETTLED: int32 = 1;
const USER_EFFECT: int32 = 2;
const NEXT_MICROTASK: int32 = 3;

function Settles(props: { mode: int32; set: Setter<boolean> }): NeonNode {
	if (props.mode === ON_SETTLED) {
		onSettled((): Cleanup | null => { props.set(true); return null; });
	}
	if (props.mode === USER_EFFECT) {
		createEffect<boolean>(
			(p: boolean | null): boolean => true,
			(v: boolean, p: boolean | null): Cleanup | null => { props.set(true); return null; },
		);
	}
	if (props.mode === NEXT_MICROTASK) {
		onSettled((): Cleanup | null => {
			Promise.resolve(0).then((u: int32): void => { props.set(true); });
			return null;
		});
	}
	return <Text>page</Text>;
}

function shell(checked: Accessor<boolean>, set: Setter<boolean>, mode: int32, headerFirst: boolean): NeonNode {
	if (headerFirst) { return <View><Header checked={checked} /><Settles mode={mode} set={set} /></View>; }
	return <View><Settles mode={mode} set={set} /><Header checked={checked} /></View>;
}

function servedShell(checked: boolean, headerFirst: boolean): MockNode {
	const [c, s] = createSignal(checked);
	return served(shell(c, s, 0, headerFirst));
}

function pageOf(view: MockNode): MockNode | null {
	for (const child of view.children) {
		if (mockToString(child) === "<text>page</text>") { return child; }
	}
	return null;
}

async function settledWrite(mode: int32, headerFirst: boolean): Promise<string> {
	resetErrorHalt();
	const root = servedShell(false, headerFirst);
	const view = root.children[0];
	const page = pageOf(view);
	const [checked, setChecked] = createSignal(false);
	const dispose = hydrate(shell(checked, setChecked, mode, headerFirst), mockHost(), root as unknown as HostNode);
	await Promise.resolve(0);
	flush();
	const kept = root.children[0] === view && page !== null && pageOf(view) === page;
	const shown = mockToString(root);
	dispose();
	const want = mockToString(servedShell(true, headerFirst));
	if (!kept) { return "the served nodes were replaced: " + shown; }
	return shown === want ? "ok" : shown;
}

test "an onSettled write during hydrate switches a sibling Show after the pass and keeps the served nodes" {
	const first = await settledWrite(ON_SETTLED, true);
	assert first === "ok", "header first: " + first;
	const last = await settledWrite(ON_SETTLED, false);
	assert last === "ok", "header last: " + last;
}

test "a createEffect write during hydrate switches a sibling Show after the pass and keeps the served nodes" {
	const first = await settledWrite(USER_EFFECT, true);
	assert first === "ok", "header first: " + first;
	const last = await settledWrite(USER_EFFECT, false);
	assert last === "ok", "header last: " + last;
}

test "control: a write one microtask after the pass hydrates and switches the Show" {
	const first = await settledWrite(NEXT_MICROTASK, true);
	assert first === "ok", "header first: " + first;
	const last = await settledWrite(NEXT_MICROTASK, false);
	assert last === "ok", "header last: " + last;
}

function marked(log: string[], value: string): void {
	log.push(value + (hydrating() ? "@claim" : ""));
}

function Counted(props: { log: string[]; writes: int32[]; viaEffect: boolean }): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	const shown = createMemo<int32>((p: int32 | null): int32 => count());
	createRenderEffect<int32>((p: int32 | null): int32 => shown(), (v: int32, p: int32 | null): Cleanup | null => {
		marked(props.log, v.toString());
		return null;
	});
	const write = (): void => {
		for (const w of props.writes) { setCount(w); }
	};
	if (props.viaEffect) {
		createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => { write(); return null; });
	} else {
		onSettled((): Cleanup | null => { write(); return null; });
	}
	return <Text>count</Text>;
}

function countedLog(writes: int32[], viaEffect: boolean, hydrated: boolean): string {
	const servedLog: string[] = [];
	const root = served(<Counted log={servedLog} writes={[]} viaEffect={viaEffect} />);
	const log: string[] = [];
	let dispose = (): void => {};
	if (hydrated) {
		dispose = hydrate(<Counted log={log} writes={writes} viaEffect={viaEffect} />, mockHost(), root as unknown as HostNode);
	} else {
		dispose = render(<Counted log={log} writes={writes} viaEffect={viaEffect} />, mockHost(), mockNode("root") as unknown as HostNode, "");
	}
	flush();
	dispose();
	return log.join(",");
}

test "an onSettled write during the hydration pass is held until the pass ends, then replays" {
	const log = countedLog([1], false, true);
	assert log === "0@claim,1", log;
}

test "a createEffect write during the hydration pass is held until the pass ends, then replays" {
	const log = countedLog([1], true, true);
	assert log === "0@claim,1", log;
}

test "outside hydration the same write applies in the same flush" {
	const log = countedLog([1], false, false);
	assert log === "0,1", log;
}

test "several writes during the pass hold the value from before the first and replay only the last" {
	const log = countedLog([1, 2, 3], false, true);
	assert log === "0@claim,3", log;
}

test "a write and a write back during the pass leave the reader's effect alone" {
	const log = countedLog([1, 0], false, true);
	assert log === "0@claim", log;
}

class Seen {
	owner: Computation | null = null;
	memo: Accessor<boolean> = accessor((): boolean => false);
	heldInPass: string = "";
}

function Watcher(props: { flag: Accessor<boolean>; setFlag: Setter<boolean>; seen: Seen; write: boolean }): NeonNode {
	const seen = props.seen;
	seen.owner = getOwner();
	seen.memo = createMemo<boolean>((p: boolean | null): boolean => props.flag());
	if (props.write) {
		onSettled((): Cleanup | null => {
			props.setFlag(true);
			seen.heldInPass = seen.memo() ? "true" : "false";
			return null;
		});
	}
	return <Text>watch</Text>;
}

function watched(seen: Seen, flag: Accessor<boolean>, setFlag: Setter<boolean>): MockNode {
	const [f, s] = createSignal(false);
	const root = served(<Watcher flag={f} setFlag={s} seen={new Seen()} write={false} />);
	hydrate(<Watcher flag={flag} setFlag={setFlag} seen={seen} write={true} />, mockHost(), root as unknown as HostNode);
	return root;
}

test "a memo created in the pass is held during it and replays after it" {
	const seen = new Seen();
	const [flag, setFlag] = createSignal(false);
	watched(seen, flag, setFlag);
	assert seen.heldInPass === "false", "the pass's memo holds the served value: " + seen.heldInPass;
	assert seen.memo(), "the memo replays once the pass is over";
}

test "a memo created after the pass under the hydrated owner reads writes live" {
	const seen = new Seen();
	const [flag, setFlag] = createSignal(false);
	watched(seen, flag, setFlag);
	const late = runWithOwner(seen.owner, (): Accessor<boolean> => createMemo<boolean>((p: boolean | null): boolean => flag()));
	setFlag(false);
	flush();
	assert !late(), "live after the pass";
}

function Effected(props: { log: string[]; write: boolean }): NeonNode {
	const [flag, setFlag] = createSignal(false);
	createEffect<boolean>((p: boolean | null): boolean => flag(), (v: boolean, p: boolean | null): Cleanup | null => {
		marked(props.log, v ? "true" : "false");
		return null;
	});
	if (props.write) { onSettled((): Cleanup | null => { setFlag(true); return null; }); }
	return <Text>effect</Text>;
}

test "an effect in the pass that reads the written signal tracked gets the served value, then reruns after the pass" {
	const root = served(<Effected log={[]} write={false} />);
	const log: string[] = [];
	const dispose = hydrate(<Effected log={log} write={true} />, mockHost(), root as unknown as HostNode);
	assert log.join(",") === "false@claim,true", log.join(",");
	dispose();
}

interface Account { checked: boolean; }
interface Row { label: string; }

function StoreHeader(props: { checked: () => boolean }): NeonNode {
	return <Show when={props.checked()} fallback={<Text>sign in</Text>}><Text>me</Text></Show>;
}

function StorePage(props: { write: boolean }): NeonNode {
	const [account, setAccount] = createStore<Account>({ checked: false });
	const [list, setList] = createStore<{ items: Row[] }>({ items: [{ label: "remove" }, { label: "keep" }] });
	const labels = createMemo<string>((p: string | null): string => {
		const out: string[] = [];
		for (let i = 0; i < list.items.length; i += 1) { out.push(list.items[i].label); }
		return out.join(",");
	});
	if (props.write) {
		onSettled((): Cleanup | null => {
			setAccount((a) => { a.checked = true; });
			setList((l) => { l.items.splice(0, 1); });
			return null;
		});
	}
	return <View>
		<StoreHeader checked={(): boolean => account.checked} />
		<Show when={list.items.length === 2} fallback={<Text>one row</Text>}><Text>two rows</Text></Show>
		<Text>{labels()}</Text>
	</View>;
}

test "a store field and a store array written during the pass switch their readers after it and keep the served nodes" {
	resetErrorHalt();
	const root = served(<StorePage write={false} />);
	const view = root.children[0];
	const dispose = hydrate(<StorePage write={true} />, mockHost(), root as unknown as HostNode);
	const shown = mockToString(root);
	assert root.children[0] === view, "the served <view> is kept: " + shown;
	assert shown.indexOf("<text>me</text>") >= 0 && shown.indexOf("one row") >= 0 && shown.indexOf(">keep<") >= 0 && shown.indexOf("remove") < 0, shown;
	dispose();
}

function laterWriteIsLive(): boolean {
	const [x, setX] = createSignal<int32>(0);
	let read: Accessor<int32> = accessor((): int32 => -1);
	createRoot((d) => {
		markSnapshotScope(getOwner() as Computation);
		read = createMemo<int32>((p: int32 | null): int32 => x());
		return 0;
	});
	setX(1);
	flush();
	return read() === 1;
}

function pendingPage(gate: Gate, flag: Accessor<boolean>): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo<int32>((p: int32 | null): Promise<int32> => gated(gate, 8 as int32));
		el("div", [], [], (h: Host, p: HostNode, b: HostNode | null): void => {
			Header({ checked: flag })(h, p, b);
			Loading({
				fallback: el("b", [], [], text("wait")),
				children: (h2: Host, p2: HostNode, b2: HostNode | null): void => {
					const n = data();
					el("p", [], [], text("n" + n.toString()))(h2, p2, b2);
				},
			})(h, p, b);
		})(host, parent, before);
	};
}

test "a Loading still pending when hydrate returns leaves no capture on: a later write is live and the content lands live" {
	resetErrorHalt();
	const servedGate = new Gate();
	const [f, s] = createSignal(false);
	const root = served(pendingPage(servedGate, f));
	const gate = new Gate();
	const [flag, setFlag] = createSignal(false);
	const dispose = hydrate(pendingPage(gate, flag), mockHost(), root as unknown as HostNode);
	assert laterWriteIsLive(), "capture ended with the pass";
	setFlag(true);
	flush();
	assert mockToString(root).indexOf("<text>me</text>") >= 0, "the write lands at once: " + mockToString(root);
	await release(gate);
	assert mockToString(root).indexOf("n8") >= 0, "the content landed: " + mockToString(root);
	dispose();
}

function Thrower(props: { fail: boolean }): NeonNode {
	onSettled((): Cleanup | null => null);
	if (props.fail) { throw new Error("boom in the pass"); }
	return <Text>fine</Text>;
}

test "a hydrate whose pass throws leaves no capture on" {
	resetErrorHalt();
	const root = served(<Thrower fail={false} />);
	let message = "";
	try {
		hydrate(<Thrower fail={true} />, mockHost(), root as unknown as HostNode);
	} catch (e) {
		message = e.message;
	}
	resetErrorHalt();
	assert message === "boom in the pass", "got [" + message + "]";
	assert !hydrating(), "the claim ended";
	assert laterWriteIsLive(), "capture ended";
}

test "a refused hydrate leaves no capture on, whether it throws or renders fresh" {
	resetErrorHalt();
	const root = served(<View><Text>a</Text><Text>b</Text></View>);
	let message = "";
	try {
		const dispose = hydrate(<View><Text>a</Text></View>, mockHost(), root as unknown as HostNode);
		dispose();
	} catch (e) {
		message = `${e}`;
	}
	resetErrorHalt();
	when (debug) {
		assert message.indexOf("hydrate:") >= 0, "a debug build throws the refusal: [" + message + "]";
	} else {
		assert message === "", "a release build renders fresh: [" + message + "]";
	}
	assert !hydrating(), "the claim ended";
	assert laterWriteIsLive(), "capture ended";
}

function waitingPage(log: string[], setFlag: Setter<boolean>, flag: Accessor<boolean>, write: boolean): NeonNode {
	return <View>
		<Header checked={flag} />
		<Settles mode={write ? ON_SETTLED : 0} set={setFlag} />
	</View>;
}

test "a hydrate disposed while it waits for a lazy module never turns capture on" {
	resetErrorHalt();
	const gate = new Gate();
	lazyModule("tests/render/hydrateWrites/disposed", (): Promise<(props: { label: string }) => NeonNode> => gated(gate, (props: { label: string }): NeonNode => <Text>{props.label}</Text>));
	putModule("0", "tests/render/hydrateWrites/disposed");
	const root = servedShell(false, true);
	const [flag, setFlag] = createSignal(false);
	const dispose = hydrate(shell(flag, setFlag, ON_SETTLED, true), mockHost(), root as unknown as HostNode);
	assert laterWriteIsLive(), "no capture while the module loads";
	dispose();
	await release(gate);
	assert !hydrating(), "nothing claimed";
	assert laterWriteIsLive(), "no capture after the load";
	clearRecords();
}

test "hydrates that wait for a lazy module hold each pass's writes in turn and leave no capture on" {
	resetErrorHalt();
	const gate = new Gate();
	lazyModule("tests/render/hydrateWrites/two", (): Promise<(props: { label: string }) => NeonNode> => gated(gate, (props: { label: string }): NeonNode => <Text>{props.label}</Text>));
	putModule("0", "tests/render/hydrateWrites/two");
	const first = servedShell(false, true);
	const second = servedShell(false, false);
	const firstView = first.children[0];
	const secondView = second.children[0];
	const [a, setA] = createSignal(false);
	const [b, setB] = createSignal(false);
	const disposeFirst = hydrate(shell(a, setA, ON_SETTLED, true), mockHost(), first as unknown as HostNode);
	const disposeSecond = hydrate(shell(b, setB, ON_SETTLED, false), mockHost(), second as unknown as HostNode);
	assert !hydrating(), "both wait for the module";
	await release(gate);
	flush();
	assert first.children[0] === firstView && second.children[0] === secondView, "both kept their served nodes";
	assert mockToString(first) === mockToString(servedShell(true, true)), mockToString(first);
	assert mockToString(second) === mockToString(servedShell(true, false)), mockToString(second);
	assert laterWriteIsLive(), "no capture after both";
	disposeFirst();
	disposeSecond();
	clearRecords();
}
