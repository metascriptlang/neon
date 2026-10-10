import { reload, lastReload, reloadKindName, ReloadKind } from "std/hcr";
import { exists, remove } from "std/fs";
import { HostNode, MockNode, mockNode, mockHost, render, fireEvent, mockToString } from "../../src/render/host";
import { Panel } from "./panel";

const STOP = "../refreshNative.stop";
const POKE = "../refreshNative.poke";

function byId(n: MockNode, id: string): MockNode | null {
	for (const a of n.attrs) {
		if (a.name === "id" && (a.value ?? "") === id) { return n; }
	}
	for (const c of n.children) {
		const b = byId(c, id);
		if (b !== null) { return b; }
	}
	return null;
}

function countTag(n: MockNode, tag: string): int32 {
	let k = (n.tag === tag ? 1 : 0) as int32;
	for (const c of n.children) { k += countTag(c, tag); }
	return k;
}

function handlers(root: MockNode, id: string): int32 {
	const b = byId(root, id);
	if (b === null) { return -1 as int32; }
	let k = 0 as int32;
	for (const e of b.events) {
		if (e.name === "onPress") { k += 1; }
	}
	return k;
}

function click(root: MockNode, id: string, times: int32): void {
	for (let i = 0 as int32; i < times; i += 1) {
		const b = byId(root, id);
		if (b !== null) { fireEvent(b, "onPress"); }
	}
}

function report(root: MockNode, tag: string): void {
	console.log(`RN ${tag} view ${mockToString(root)}`);
	console.log(`RN ${tag} counters=${countTag(root, "h2")} incHandlers=${handlers(root, "inc")} tallyHandlers=${handlers(root, "tally")}`);
	click(root, "inc", 1);
	console.log(`RN ${tag} click ${mockToString(root)}`);
}

const root: MockNode = mockNode("root");
const dispose = render(Panel(), mockHost(), root as unknown as HostNode);
click(root, "inc", 8);
click(root, "tally", 5);
console.log("RN start " + mockToString(root));
console.log("RN ready");
let frames = 0;
let events = 0;
while (frames < 30000 && !exists(STOP)) {
	const kind = reload();
	if (kind != ReloadKind.NoChange && kind != ReloadKind.Pending) {
		events += 1;
		const r = lastReload();
		console.log(`RN event${events} ${reloadKindName(kind)} [${r.modules.join(",")}] ${r.reason}`);
		report(root, `event${events}`);
		console.log(`RN settled ${events}`);
	}
	if (exists(POKE)) {
		const gone = remove(POKE);
		report(root, "poke");
		console.log("RN poke done");
	}
	await sleepAsync(16);
	frames += 1;
}
dispose();
console.log("RN done");
