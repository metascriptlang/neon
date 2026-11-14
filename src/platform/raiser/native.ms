import {
	createInterpreter, evalModule, selectRoutine, callRoutine, implementRoutine,
	runDueTimers, nextTimerDelayMs, unboxValue, boxValue,
	Interpreter, Routine, Diagnostic, System, RaiserValue, RaiserValueKind, RaiserHostValue,
	boxInt, boxFloat, boxBool, boxVoid, unboxInt, unboxFloat, unboxString, unboxBool,
	hostValue, hostString, hostObject, hostArray,
} from "../../../../recompiler/src/embed/index";
import { applyProjectConfig } from "../../../../recompiler/src/compiler/options";
import { ErrorSeverity } from "../../../../recompiler/src/module/graph";
import { Host, HostNode, NeonNode, TextSpan, MeasureRect, MeasureError } from "../../render/hostTypes";
import { Style, emptyStyle, setStyleField } from "../../render/style";
import { styleTable } from "../../macros/style/fields";
import { NeonEvent } from "../../render/event";
import { Row, place, makeRow, mountApart, removeRow } from "../../render/reconcile";
import { createSignal, Setter } from "../../core/signal";
import { createRoot } from "../../core/owner";
import { onCleanup } from "../../core/cleanup";
import { flush } from "../../core/runtime";
import { Dispose } from "../../core/types";
import {
	NO_NODE, NO_HANDLER, REGION, REGION_END, GENERATIONS, MEASURE_ERRORS,
	CAN_PARAGRAPH, CAN_FOCUS, CAN_SCROLL_TO, CAN_MEASURE_TEXT, CAN_MEASURE_IN_WINDOW, CAN_MEASURE_LAYOUT,
	handleAt, handleIndex, handleGeneration,
} from "./wire";
import { homeDir } from "std/os";
import { realpath } from "std/fs";

export {
	Diagnostic, RaiserHostValue, hostValue, hostString, hostObject, hostArray, boxInt, boxFloat, boxBool, unboxInt,
} from "../../../../recompiler/src/embed/index";

const STYLE_TABLE: string[][] = styleTable();

export class GuestProgram {
	interp: Interpreter;
	generation: int32 = 0;
	dispatch: Routine | null = null;
	dispose: Routine | null = null;
	slots: SlotHandle[] = [];
	wake: number = -1;
	running: boolean = false;
	onError: (message: string) => void = (message: string): void => { throw new Error(message); };

	constructor(interp: Interpreter) {
		this.interp = interp;
	}
}

export enum SlotOutcome {
	Mounted,
	EvalFailed,
	MissingExports,
	MissingView,
	ViewThrew,
}

export enum SlotShown {
	Nothing,
	Guest,
	InertGuest,
	Fallback,
}

export interface SlotRoot {
	key: int32;
	generation: int32;
}

export interface SlotStatus {
	outcome: SlotOutcome;
	shown: SlotShown;
	root: SlotRoot | null;
}

export class SlotHandle {
	program: GuestProgram;
	view: string;
	args: RaiserHostValue[];
	host: Host;
	start: HostNode;
	end: HostNode;
	fallback: NeonNode | null;
	root: BridgeRoot | null = null;
	fallbackRow: Row | null = null;
	disposeFallback: Dispose | null = null;
	outcome: SlotOutcome = SlotOutcome.Mounted;
	closed: boolean = false;

	constructor(
		program: GuestProgram,
		view: string,
		args: RaiserHostValue[],
		host: Host,
		start: HostNode,
		end: HostNode,
		fallback: NeonNode | null,
	) {
		this.program = program;
		this.view = view;
		this.args = args;
		this.host = host;
		this.start = start;
		this.end = end;
		this.fallback = fallback;
	}
}

class SpanFeed {
	write: Setter<TextSpan[]>;
	dispose: Dispose;

	constructor(write: Setter<TextSpan[]>, dispose: Dispose) {
		this.write = write;
		this.dispose = dispose;
	}
}

class BridgeRoot {
	key: int32;
	program: GuestProgram;
	generation: int32;
	slot: SlotHandle;
	host: Host;
	nodes: (HostNode | null)[] = [];
	generations: int32[] = [];
	idle: int32[] = [];
	handles: Map<HostNode, int32> = new Map<HostNode, int32>();
	feeds: Map<int32, SpanFeed> = new Map<int32, SpanFeed>();
	live: boolean = true;

	constructor(key: int32, slot: SlotHandle) {
		this.key = key;
		this.program = slot.program;
		this.generation = slot.program.generation;
		this.slot = slot;
		this.host = slot.host;
		this.nodes.push(null);
		this.generations.push(0);
		this.nodes.push(slot.end);
		this.generations.push(0);
		this.handles.set(slot.end, REGION_END);
	}
}

const bridgeRoots = new Map<int32, BridgeRoot>();
let nextKey: int32 = 1;
let calling: GuestProgram | null = null;
let registered = false;

function guestCall<T>(p: GuestProgram, run: () => T): T {
	if (p.running) { throw new Error("a native event re-entered its guest interpreter while a guest call was running"); }
	const outer = calling;
	calling = p;
	p.running = true;
	try {
		return run();
	} finally {
		p.running = false;
		calling = outer;
	}
}

function disarm(p: GuestProgram): void {
	if (p.wake < 0) { return; }
	clearTimeout(p.wake);
	p.wake = -1;
}

function arm(p: GuestProgram): void {
	disarm(p);
	const delay = nextTimerDelayMs(p.interp);
	if (delay < 0) { return; }
	p.wake = setTimeout((): void => {
		p.wake = -1;
		pump(p);
	}, delay);
}

function pump(p: GuestProgram): void {
	const failures: string[] = [];
	guestCall(p, (): int32 => {
		let ran = runDueTimers(p.interp);
		while (!ran.ok) {
			failures.push(ran.error);
			ran = runDueTimers(p.interp);
		}
		return 0;
	});
	arm(p);
	for (const failure of failures) { p.onError(failure); }
}

function invoke(p: GuestProgram, routine: Routine, args: RaiserHostValue[]): Result<RaiserHostValue, string> {
	const got = guestCall(p, (): Result<RaiserHostValue, string> => callRoutine(p.interp, routine, args));
	arm(p);
	return got;
}

export function callGuest(p: GuestProgram, name: string, args: RaiserHostValue[]): Result<RaiserHostValue, string> {
	const selected = selectRoutine(p.interp, name);
	if (!selected.ok) { return Result.err(selected.error); }
	return invoke(p, selected.value, args);
}

function rootOf(args: RaiserValue[]): BridgeRoot {
	const key = unboxInt(args[0]) as int32;
	const r = bridgeRoots.get(key);
	if (r === undefined) { throw new Error(`a ui call names guest root ${key}, which is not mounted`); }
	if (r.program !== calling) { throw new Error(`a ui call names guest root ${key}, which belongs to another interpreter`); }
	return r;
}

function regionParent(r: BridgeRoot): HostNode {
	const parent = r.host.parentOf(r.slot.end);
	if (parent === null) { throw new Error(`guest root ${r.key}: its slot is no longer in the tree`); }
	return parent as HostNode;
}

function nodeAt(r: BridgeRoot, handle: int32): HostNode {
	if (handle === REGION) { return regionParent(r); }
	const at = handleIndex(handle);
	const node = at < r.nodes.length ? r.nodes[at] : null;
	if (node === null || r.generations[at] !== handleGeneration(handle)) {
		throw new Error(`guest root ${r.key} holds no node ${handle}: it was freed or never made`);
	}
	return node as HostNode;
}

function nodeArg(r: BridgeRoot, args: RaiserValue[], index: int32): HostNode {
	return nodeAt(r, unboxInt(args[index]) as int32);
}

function handleOf(r: BridgeRoot, node: HostNode | null): int32 {
	if (node === null) { return NO_NODE; }
	const known = r.handles.get(node as HostNode);
	if (known !== undefined) { return known; }
	if (node === regionParent(r)) { return REGION; }
	throw new Error(`guest root ${r.key} reached a node outside its slot`);
}

function add(r: BridgeRoot, node: HostNode): RaiserValue {
	let at = r.nodes.length as int32;
	if (r.idle.length > 0) {
		at = r.idle.pop() as int32;
		r.nodes[at] = node;
	} else {
		r.nodes.push(node);
		r.generations.push(0);
	}
	const handle = handleAt(at, r.generations[at]);
	r.handles.set(node, handle);
	return boxInt(handle);
}

function collect(r: BridgeRoot, node: HostNode, freed: int32[]): void {
	const handle = r.handles.get(node);
	if (handle !== undefined) { freed.push(handle); }
	let child = r.host.firstChild(node);
	while (child !== null) {
		collect(r, child as HostNode, freed);
		child = r.host.nextSibling(child as HostNode);
	}
}

function forget(r: BridgeRoot, handle: int32): void {
	const at = handleIndex(handle);
	const node = r.nodes[at];
	if (node !== null) { r.handles.delete(node as HostNode); }
	r.nodes[at] = null;
	r.generations[at] = (r.generations[at] + 1) % GENERATIONS;
	r.idle.push(at);
	const feed = r.feeds.get(at);
	if (feed !== undefined) {
		r.feeds.delete(at);
		feed.dispose();
	}
}

function freedList(freed: int32[]): RaiserValue {
	const items: RaiserHostValue[] = [];
	for (const handle of freed) { items.push(hostValue(boxInt(handle))); }
	return boxValue(hostArray(items));
}

function removeFrom(r: BridgeRoot, parent: HostNode, node: HostNode): int32[] {
	const freed: int32[] = [];
	collect(r, node, freed);
	r.host.removeChild(parent, node);
	for (const handle of freed) { forget(r, handle); }
	return freed;
}

function styleOf(v: RaiserHostValue): Style {
	const style = emptyStyle();
	for (const row of STYLE_TABLE) {
		const value = v.field(row[0]);
		const kind = value.root.kind;
		if (kind == RaiserValueKind.String) {
			setStyleField(style, row[0], value.text());
		} else if (kind == RaiserValueKind.Int || kind == RaiserValueKind.Float) {
			setStyleField(style, row[0], unboxFloat(value.root));
		}
	}
	return style;
}

function eventValue(e: NeonEvent): RaiserHostValue {
	return hostObject(
		[
			"type", "timeStamp", "value", "x", "y", "width", "height", "contentWidth", "contentHeight", "key", "code",
			"altKey", "ctrlKey", "metaKey", "shiftKey", "repeat", "isComposing", "scancode", "mods", "consumedMods",
			"unshifted", "text", "imeHandled", "cursor", "button", "pressed", "pointerOrigin", "locationX", "locationY",
			"deltaX", "deltaY", "deltaMode", "propagationStopped",
		],
		[
			hostString(e.type), hostValue(boxFloat(e.timeStamp)), hostString(e.value), hostValue(boxFloat(e.x)),
			hostValue(boxFloat(e.y)), hostValue(boxFloat(e.width)), hostValue(boxFloat(e.height)),
			hostValue(boxFloat(e.contentWidth)), hostValue(boxFloat(e.contentHeight)), hostString(e.key), hostString(e.code),
			hostValue(boxBool(e.altKey)), hostValue(boxBool(e.ctrlKey)), hostValue(boxBool(e.metaKey)),
			hostValue(boxBool(e.shiftKey)), hostValue(boxBool(e.repeat)), hostValue(boxBool(e.isComposing)),
			hostValue(boxFloat(e.scancode)), hostValue(boxFloat(e.mods)), hostValue(boxFloat(e.consumedMods)),
			hostValue(boxFloat(e.unshifted)), hostString(e.text), hostValue(boxBool(e.imeHandled)),
			hostValue(boxFloat(e.cursor)), hostValue(boxFloat(e.button)), hostValue(boxBool(e.pressed)),
			hostValue(boxBool(e.pointerOrigin)), hostValue(boxFloat(e.locationX)), hostValue(boxFloat(e.locationY)),
			hostValue(boxFloat(e.deltaX)), hostValue(boxFloat(e.deltaY)), hostValue(boxFloat(e.deltaMode)),
			hostValue(boxBool(e.propagationStopped)),
		],
	);
}

function inert(r: BridgeRoot): boolean {
	return r.generation !== r.program.generation || r.program.dispatch === null;
}

function deliverEvent(r: BridgeRoot, handler: int32, name: string, e: NeonEvent): void {
	const p = r.program;
	const dispatch = p.dispatch;
	if (!r.live) {
		p.onError(`guest root ${r.key} refused ${name}: the root was retired`);
		return;
	}
	if (inert(r) || dispatch === null) {
		p.onError(`guest root ${r.key} refused ${name}: it is inert, mounted by program generation ${r.generation} and replaced by generation ${p.generation}`);
		return;
	}
	const got = invoke(p, dispatch, [hostValue(boxInt(r.key)), hostValue(boxInt(handler)), hostString(name), eventValue(e)]);
	if (!got.ok) {
		p.onError(got.error);
		return;
	}
	if (unboxBool(got.value.root)) { e.propagationStopped = true; }
}

function eventTo(r: BridgeRoot, handler: int32, name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => { deliverEvent(r, handler, name, e); };
}

function touchTo(r: BridgeRoot, handler: int32): (name: string, e: NeonEvent) => void {
	return (name: string, e: NeonEvent): void => { deliverEvent(r, handler, name, e); };
}

function setSpans(r: BridgeRoot, args: RaiserValue[]): void {
	const handle = unboxInt(args[1]) as int32;
	const node = nodeAt(r, handle);
	const texts = unboxValue(args[2]);
	const styles = unboxValue(args[3]);
	const presses = unboxValue(args[4]);
	const touches = unboxValue(args[5]);
	const spans: TextSpan[] = [];
	for (let i: int32 = 0; i < texts.length(); i += 1) {
		const span: TextSpan = { text: texts.at(i).text() };
		const style = styles.at(i);
		if (style.root.kind != RaiserValueKind.Nil) { span.style = styleOf(style); }
		const press = unboxInt(presses.at(i).root) as int32;
		if (press != NO_HANDLER) { span.onPress = eventTo(r, press, "onPress"); }
		const touch = unboxInt(touches.at(i).root) as int32;
		if (touch != NO_HANDLER) { span.onTouch = touchTo(r, touch); }
		spans.push(span);
	}
	const at = handleIndex(handle);
	const feed = r.feeds.get(at);
	if (feed !== undefined) {
		feed.write(spans);
		return;
	}
	const host = r.host;
	const paragraph = host.paragraph;
	if (paragraph === null) { throw new Error("the guest delivered spans to a host that draws no paragraph"); }
	createRoot((dispose: Dispose): void => {
		const [read, write] = createSignal<TextSpan[]>(spans);
		r.feeds.set(at, new SpanFeed(write, dispose));
		paragraph(host, node, null, null, read);
	});
}

function capabilitiesOf(host: Host): int32 {
	let capabilities: int32 = 0;
	const paragraph = host.paragraph;
	const focus = host.focus;
	const inWindow = host.measureInWindow;
	const inLayout = host.measureLayout;
	if (paragraph !== null) { capabilities |= CAN_PARAGRAPH; }
	if (focus !== null) { capabilities |= CAN_FOCUS; }
	if (host.scrollTo !== null) { capabilities |= CAN_SCROLL_TO; }
	if (host.measureText !== null) { capabilities |= CAN_MEASURE_TEXT; }
	if (inWindow !== null) { capabilities |= CAN_MEASURE_IN_WINDOW; }
	if (inLayout !== null) { capabilities |= CAN_MEASURE_LAYOUT; }
	return capabilities;
}

function measureOf(r: BridgeRoot, args: RaiserValue[]): RaiserValue {
	const node = nodeArg(r, args, 1);
	const ancestor = unboxInt(args[2]) as int32;
	const inWindow = r.host.measureInWindow;
	const inLayout = r.host.measureLayout;
	let read: Result<MeasureRect, MeasureError> = Result.err(MEASURE_ERRORS[3]);
	if (ancestor === NO_NODE && inWindow !== null) { read = inWindow(node); }
	if (ancestor !== NO_NODE && inLayout !== null) { read = inLayout(node, nodeAt(r, ancestor)); }
	const out: RaiserHostValue[] = [];
	if (read.ok) {
		out.push(hostValue(boxFloat(-1)));
		out.push(hostValue(boxFloat(read.value.x)));
		out.push(hostValue(boxFloat(read.value.y)));
		out.push(hostValue(boxFloat(read.value.width)));
		out.push(hostValue(boxFloat(read.value.height)));
	} else {
		out.push(hostValue(boxFloat(MEASURE_ERRORS.indexOf(read.error) as number)));
		for (let i = 0; i < 4; i += 1) { out.push(hostValue(boxFloat(0))); }
	}
	return boxValue(hostArray(out));
}

function measureTextOf(r: BridgeRoot, args: RaiserValue[]): RaiserValue {
	const measure = r.host.measureText;
	if (measure === null) { throw new Error("the guest measured text on a host that measures none"); }
	const m = measure(unboxString(args[1]), styleOf(unboxValue(args[2])));
	return boxValue(hostArray([
		hostValue(boxFloat(m.width)), hostValue(boxFloat(m.height)),
		hostValue(boxFloat(m.ascender)), hostValue(boxFloat(m.descender)),
	]));
}

function firstChildOf(r: BridgeRoot, handle: int32): HostNode | null {
	if (handle !== REGION) { return r.host.firstChild(nodeAt(r, handle)); }
	let at = r.host.nextSibling(r.slot.start);
	while (at !== null && at !== r.slot.end && !r.handles.has(at as HostNode)) { at = r.host.nextSibling(at as HostNode); }
	return at;
}

function done(): RaiserValue {
	return boxVoid();
}

function implementUi(): void {
	implementRoutine("ui.capabilities", (a: RaiserValue[]): RaiserValue => boxInt(capabilitiesOf(rootOf(a).host)));
	implementRoutine("ui.createElement", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		return add(r, r.host.createElement(unboxString(a[1])));
	});
	implementRoutine("ui.createText", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		return add(r, r.host.createText(unboxString(a[1])));
	});
	implementRoutine("ui.setText", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		r.host.setText(nodeArg(r, a, 1), unboxString(a[2]));
		return done();
	});
	implementRoutine("ui.setAttr", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		r.host.setAttr(nodeArg(r, a, 1), unboxString(a[2]), unboxString(a[3]));
		return done();
	});
	implementRoutine("ui.removeAttr", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		r.host.removeAttr(nodeArg(r, a, 1), unboxString(a[2]));
		return done();
	});
	implementRoutine("ui.setStyle", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		r.host.setStyle(nodeArg(r, a, 1), styleOf(unboxValue(a[2])));
		return done();
	});
	implementRoutine("ui.addEvent", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		const name = unboxString(a[2]);
		r.host.addEvent(nodeArg(r, a, 1), name, eventTo(r, unboxInt(a[3]) as int32, name));
		return done();
	});
	implementRoutine("ui.append", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		const parent = unboxInt(a[1]) as int32;
		if (parent === REGION) {
			r.host.insertBefore(regionParent(r), nodeArg(r, a, 2), r.slot.end);
		} else {
			r.host.append(nodeAt(r, parent), nodeArg(r, a, 2));
		}
		return done();
	});
	implementRoutine("ui.insertBefore", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		const parent = unboxInt(a[1]) as int32;
		const before = unboxInt(a[3]) as int32;
		const at = before !== NO_NODE ? nodeAt(r, before) : parent === REGION ? r.slot.end : null;
		r.host.insertBefore(nodeAt(r, parent), nodeArg(r, a, 2), at);
		return done();
	});
	implementRoutine("ui.removeChild", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		return freedList(removeFrom(r, nodeArg(r, a, 1), nodeArg(r, a, 2)));
	});
	implementRoutine("ui.release", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		const node = nodeArg(r, a, 1);
		const freed: int32[] = [];
		collect(r, node, freed);
		r.host.release(node);
		for (const handle of freed) { forget(r, handle); }
		return freedList(freed);
	});
	implementRoutine("ui.parentOf", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		return boxInt(handleOf(r, r.host.parentOf(nodeArg(r, a, 1))));
	});
	implementRoutine("ui.nextSibling", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		return boxInt(handleOf(r, r.host.nextSibling(nodeArg(r, a, 1))));
	});
	implementRoutine("ui.firstChild", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		return boxInt(handleOf(r, firstChildOf(r, unboxInt(a[1]) as int32)));
	});
	implementRoutine("ui.setSpans", (a: RaiserValue[]): RaiserValue => {
		setSpans(rootOf(a), a);
		return done();
	});
	implementRoutine("ui.focus", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		const focus = r.host.focus;
		if (focus === null) { throw new Error("the guest focused a node on a host that focuses none"); }
		focus(nodeArg(r, a, 1), unboxBool(a[2]));
		return done();
	});
	implementRoutine("ui.scrollTo", (a: RaiserValue[]): RaiserValue => {
		const r = rootOf(a);
		const scroll = r.host.scrollTo;
		if (scroll === null) { throw new Error("the guest scrolled a node on a host that scrolls none"); }
		scroll(nodeArg(r, a, 1), unboxFloat(a[2]), unboxFloat(a[3]), unboxBool(a[4]));
		return done();
	});
	implementRoutine("ui.measureText", (a: RaiserValue[]): RaiserValue => measureTextOf(rootOf(a), a));
	implementRoutine("ui.measure", (a: RaiserValue[]): RaiserValue => measureOf(rootOf(a), a));
}

function select(p: GuestProgram, name: string): Routine | null {
	const selected = selectRoutine(p.interp, name);
	return selected.ok ? selected.value : null;
}

const MISSING_EXPORTS = "a guest program re-exports raiserDispatch and raiserDispose from neon's src/platform/raiser/guest";

function guestError(path: string, message: string): Diagnostic {
	return { file: path, line: 0, column: 0, message, severity: ErrorSeverity.Error };
}

export interface GuestOptions {
	projectRoot: string;
	runtimeRoot?: string | null;
	system?: System | null;
}

export function openGuest(options: GuestOptions): Result<GuestProgram, string> {
	if (!registered) {
		implementUi();
		registered = true;
	}
	const runtimeRoot = options.runtimeRoot ?? `${homeDir()}/.metascript`;
	const made = createInterpreter(runtimeRoot, [], options.system ?? null);
	if (!made.ok) { return Result.err(made.error); }
	const configured = applyProjectConfig(made.value.opts, realpath(options.projectRoot));
	if (!configured.ok) { return Result.err(configured.error); }
	return Result.ok(new GuestProgram(made.value));
}

export function loadGuest(p: GuestProgram, path: string): Result<int32, Diagnostic[]> {
	const ran = guestCall(p, (): Result<int32, Diagnostic[]> => {
		const evaluated = evalModule(p.interp, path);
		return evaluated.ok ? Result.ok(0) : Result.err(evaluated.error);
	});
	arm(p);
	if (!ran.ok) {
		for (const slot of p.slots) { slot.outcome = SlotOutcome.EvalFailed; }
		return Result.err(ran.error);
	}
	p.generation += 1;
	p.dispatch = select(p, "raiserDispatch");
	p.dispose = select(p, "raiserDispose");
	if (p.dispatch === null || p.dispose === null) {
		for (const slot of p.slots.slice(0)) { failSlot(slot, SlotOutcome.MissingExports); }
		return Result.err([guestError(path, MISSING_EXPORTS)]);
	}
	const failures: string[] = [];
	for (const slot of p.slots.slice(0)) {
		const failed = mountSlot(slot);
		if (failed !== null) { failures.push(failed); }
	}
	for (const failure of failures) { p.onError(failure); }
	return Result.ok(p.generation);
}

function regionNodes(r: BridgeRoot): HostNode[] {
	const owned: HostNode[] = [];
	let at = r.host.nextSibling(r.slot.start);
	while (at !== null && at !== r.slot.end) {
		if (r.handles.has(at as HostNode)) { owned.push(at as HostNode); }
		at = r.host.nextSibling(at as HostNode);
	}
	return owned;
}

function retire(r: BridgeRoot, inGuest: boolean): void {
	if (!r.live) { return; }
	const p = r.program;
	const dispose = p.dispose;
	let failure: string | null = null;
	if (inGuest && r.generation === p.generation && dispose !== null) {
		const got = invoke(p, dispose, [hostValue(boxInt(r.key))]);
		if (!got.ok) { failure = got.error; }
	}
	r.live = false;
	const parent = r.host.parentOf(r.slot.end);
	if (parent !== null) {
		for (const node of regionNodes(r)) { removeFrom(r, parent as HostNode, node); }
	}
	for (const feed of r.feeds.values()) { feed.dispose(); }
	r.feeds.clear();
	bridgeRoots.delete(r.key);
	if (failure !== null) { p.onError(failure as string); }
}

function showFallback(slot: SlotHandle, fallback: NeonNode): void {
	const parent = slot.host.parentOf(slot.end);
	if (parent === null) { throw new Error(`the guest slot for view ${slot.view} is no longer in the tree`); }
	slot.disposeFallback = createRoot((dispose: Dispose): Dispose => {
		const shown = makeRow(fallback);
		try {
			mountApart(slot.host, parent as HostNode, slot.end, shown);
			slot.fallbackRow = shown;
			return dispose;
		} catch (error) {
			dispose();
			throw error;
		}
	});
	flush();
}

function hideFallback(slot: SlotHandle): void {
	const row = slot.fallbackRow;
	const dispose = slot.disposeFallback;
	slot.fallbackRow = null;
	slot.disposeFallback = null;
	const parent = slot.host.parentOf(slot.end);
	if (row !== null && parent !== null) { removeRow(slot.host, parent as HostNode, row as Row); }
	if (dispose !== null) { dispose(); }
}

function failSlot(slot: SlotHandle, outcome: SlotOutcome): void {
	slot.outcome = outcome;
	const fallback = slot.fallback;
	if (fallback === null || slot.fallbackRow !== null) { return; }
	const old = slot.root;
	slot.root = null;
	if (old !== null) { retire(old as BridgeRoot, true); }
	showFallback(slot, fallback as NeonNode);
}

function mountSlot(slot: SlotHandle): string | null {
	const p = slot.program;
	if (p.dispatch === null || p.dispose === null) {
		failSlot(slot, SlotOutcome.MissingExports);
		return `${slot.view}: ${MISSING_EXPORTS}`;
	}
	const selected = selectRoutine(p.interp, slot.view);
	if (!selected.ok) {
		failSlot(slot, SlotOutcome.MissingView);
		return selected.error;
	}
	const r = new BridgeRoot(nextKey, slot);
	nextKey += 1;
	bridgeRoots.set(r.key, r);
	const args: RaiserHostValue[] = [hostValue(boxInt(r.key))];
	for (const arg of slot.args) { args.push(arg); }
	const got = invoke(p, selected.value, args);
	if (!got.ok) {
		retire(r, false);
		failSlot(slot, SlotOutcome.ViewThrew);
		return `${slot.view}: ${got.error}`;
	}
	const old = slot.root;
	slot.root = r;
	slot.outcome = SlotOutcome.Mounted;
	if (old !== null) { retire(old as BridgeRoot, true); }
	hideFallback(slot);
	return null;
}

export function slotStatus(slot: SlotHandle): SlotStatus {
	const r = slot.root;
	if (slot.fallbackRow !== null) { return { outcome: slot.outcome, shown: SlotShown.Fallback, root: null }; }
	if (r === null) { return { outcome: slot.outcome, shown: SlotShown.Nothing, root: null }; }
	const root = r as BridgeRoot;
	return {
		outcome: slot.outcome,
		shown: inert(root) ? SlotShown.InertGuest : SlotShown.Guest,
		root: { key: root.key, generation: root.generation },
	};
}

function startSlot(
	program: GuestProgram,
	view: string,
	args: RaiserHostValue[],
	host: Host,
	parent: HostNode,
	before: HostNode | null,
	fallback: NeonNode | null,
): SlotHandle {
	const start = host.createText("");
	place(host, parent, start, before);
	const end = host.createText("");
	place(host, parent, end, before);
	const slot = new SlotHandle(program, view, args, host, start, end, fallback);
	program.slots.push(slot);
	return slot;
}

function mountReported(slot: SlotHandle): void {
	const failed = mountSlot(slot);
	if (failed !== null) { slot.program.onError(failed as string); }
}

function release(slot: SlotHandle): void {
	if (slot.closed) { throw new Error(`the guest slot for view ${slot.view} is already closed`); }
	slot.closed = true;
	const p = slot.program;
	const at = p.slots.indexOf(slot);
	if (at >= 0) { p.slots.splice(at, 1); }
	const r = slot.root;
	slot.root = null;
	if (r !== null) { retire(r as BridgeRoot, true); }
	hideFallback(slot);
}

export function openSlot(
	program: GuestProgram,
	view: string,
	args: RaiserHostValue[],
	host: Host,
	parent: HostNode,
	before: HostNode | null,
	fallback: NeonNode | null = null,
): SlotHandle {
	const slot = startSlot(program, view, args, host, parent, before, fallback);
	try {
		mountReported(slot);
	} catch (error) {
		closeSlot(slot);
		throw error;
	}
	return slot;
}

export function closeSlot(slot: SlotHandle): void {
	release(slot);
	for (const marker of [slot.start, slot.end]) {
		const parent = slot.host.parentOf(marker);
		if (parent !== null) { slot.host.removeChild(parent as HostNode, marker); }
	}
}

export interface GuestSlotProps {
	program: GuestProgram;
	view: string;
	args?: RaiserHostValue[] | null;
	fallback?: NeonNode | null;
}

export function GuestSlot(props: GuestSlotProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const slot = startSlot(props.program, props.view, props.args ?? [], host, parent, before, props.fallback ?? null);
		onCleanup((): void => { release(slot); });
		mountReported(slot);
	};
}
