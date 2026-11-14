import { render, mockHost, Host, HostNode } from "../../src/render/host";
import { Style, emptyStyle, setStyleField } from "../../src/render/style";
import { NeonEvent } from "../../src/render/event";
import { TextSpan } from "../../src/render/hostTypes";
import { createSignal, Setter } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
import { createVoidHost, VoidHost } from "../../src/platform/void/host";
import { Rows } from "./rows";
import { homeDir } from "std/os";
import { argv } from "std/process";
import { realpath } from "std/fs";
import {
	createInterpreter, evalModule, selectRoutine, callRoutine, implementRoutine, unboxValue, machineSystem,
	RaiserValue, RaiserValueKind, RaiserHostValue, Interpreter, Routine,
	boxInt, boxFloat, boxVoid, boxBool, unboxInt, unboxString, unboxBool, hostValue,
} from "../../../../.metascript/src/embed/index";
import { applyProjectConfig } from "../../../../.metascript/src/compiler/options";

const STYLE_FIELDS = ["width", "height", "flexDirection", "backgroundColor", "flexGrow", "padding", "gap", "color"];

let host: Host = mockHost();
let nodes: HostNode[] = [];
let unboxStyles = true;
let calls = 0;

function minOf(a: number, b: number): number { return a < b ? a : b; }

function add(n: HostNode | null): int32 {
	if (n === null) { return -1; }
	nodes.push(n);
	return (nodes.length - 1) as int32;
}

function idOf(n: HostNode | null): int32 {
	if (n === null) { return -1; }
	for (let i = nodes.length - 1; i >= 0; i -= 1) {
		if (nodes[i] === n) { return i as int32; }
	}
	return add(n);
}

function nodeAt(v: RaiserValue): HostNode {
	return nodes[unboxInt(v) as int32];
}

function styleOf(v: RaiserHostValue): Style {
	const style = emptyStyle();
	if (!unboxStyles) { return style; }
	for (const name of STYLE_FIELDS) {
		const f = v.field(name);
		if (f.root.kind == RaiserValueKind.String) { setStyleField(style, name, f.text()); }
		else if (f.root.kind == RaiserValueKind.Int) { setStyleField(style, name, f.root.intVal as number); }
		else if (f.root.kind == RaiserValueKind.Float) { setStyleField(style, name, f.root.floatVal); }
	}
	return style;
}

const spanSetters = new Map<int32, Setter<TextSpan[]>>();

function setSpans(id: int32, texts: RaiserHostValue): void {
	const spans: TextSpan[] = [];
	for (let i = 0; i < texts.length(); i++) { spans.push({ text: texts.at(i as int32).text() }); }
	const known = spanSetters.get(id);
	if (known !== undefined) {
		known(spans);
		return;
	}
	const paragraph = host.paragraph;
	if (paragraph === null || paragraph === undefined) { throw new Error("the native host draws no paragraph"); }
	createRoot((dispose: () => void): void => {
		const [read, write] = createSignal<TextSpan[]>(spans);
		spanSetters.set(id, write);
		paragraph(host, nodes[id], null, null, read);
	});
}

function implement(): void {
	implementRoutine("ui.createElement", (a: RaiserValue[]): RaiserValue => { calls++; return boxInt(add(host.createElement(unboxString(a[0])))); });
	implementRoutine("ui.createText", (a: RaiserValue[]): RaiserValue => { calls++; return boxInt(add(host.createText(unboxString(a[0])))); });
	implementRoutine("ui.setText", (a: RaiserValue[]): RaiserValue => { calls++; host.setText(nodeAt(a[0]), unboxString(a[1])); return boxVoid(); });
	implementRoutine("ui.setAttr", (a: RaiserValue[]): RaiserValue => { calls++; host.setAttr(nodeAt(a[0]), unboxString(a[1]), unboxString(a[2])); return boxVoid(); });
	implementRoutine("ui.removeAttr", (a: RaiserValue[]): RaiserValue => { calls++; host.removeAttr(nodeAt(a[0]), unboxString(a[1])); return boxVoid(); });
	implementRoutine("ui.setStyle", (a: RaiserValue[]): RaiserValue => { calls++; host.setStyle(nodeAt(a[0]), styleOf(unboxValue(a[1]))); return boxVoid(); });
	implementRoutine("ui.addEvent", (a: RaiserValue[]): RaiserValue => {
		calls++;
		host.addEvent(nodeAt(a[0]), unboxString(a[1]), (e: NeonEvent): void => {});
		return boxVoid();
	});
	implementRoutine("ui.append", (a: RaiserValue[]): RaiserValue => { calls++; host.append(nodeAt(a[0]), nodeAt(a[1])); return boxVoid(); });
	implementRoutine("ui.insertBefore", (a: RaiserValue[]): RaiserValue => {
		calls++;
		const before = unboxInt(a[2]) as int32;
		host.insertBefore(nodeAt(a[0]), nodeAt(a[1]), before < 0 ? null : nodes[before]);
		return boxVoid();
	});
	implementRoutine("ui.removeChild", (a: RaiserValue[]): RaiserValue => { calls++; host.removeChild(nodeAt(a[0]), nodeAt(a[1])); return boxVoid(); });
	implementRoutine("ui.parentOf", (a: RaiserValue[]): RaiserValue => { calls++; return boxInt(idOf(host.parentOf(nodeAt(a[0])))); });
	implementRoutine("ui.release", (a: RaiserValue[]): RaiserValue => { calls++; host.release(nodeAt(a[0])); return boxVoid(); });
	implementRoutine("ui.nextSibling", (a: RaiserValue[]): RaiserValue => { calls++; return boxInt(idOf(host.nextSibling(nodeAt(a[0])))); });
	implementRoutine("ui.firstChild", (a: RaiserValue[]): RaiserValue => { calls++; return boxInt(idOf(host.firstChild(nodeAt(a[0])))); });
	implementRoutine("ui.setSpans", (a: RaiserValue[]): RaiserValue => { calls++; setSpans(unboxInt(a[0]) as int32, unboxValue(a[1])); return boxVoid(); });
}

function routine(interp: Interpreter, name: string): Routine {
	const r = selectRoutine(interp, name);
	if (!r.ok) { throw new Error(r.error); }
	return r.value;
}

function call(interp: Interpreter, name: string, args: RaiserHostValue[]): RaiserHostValue {
	const got = callRoutine(interp, routine(interp, name), args);
	if (!got.ok) { throw new Error(`${name}: ${got.error}`); }
	return got.value;
}

function fresh(kind: string): HostNode {
	nodes = [];
	spanSetters.clear();
	if (kind === "void") {
		const vh: VoidHost = createVoidHost();
		host = vh.host;
		return vh.root as unknown as HostNode;
	}
	host = mockHost();
	return host.createElement("root");
}

function line(name: string, ms: number, n: int32, extra: string): void {
	console.log(`${name} N=${n} ms=${ms.toFixed(3)} usPerRow=${(ms * 1000.0 / (n as number)).toFixed(2)}${extra}`);
}

function compiled(kind: string, n: int32, rounds: int32): void {
	const [label, setLabel] = createSignal("a");
	let mountBest = 1e18;
	let updateBest = 1e18;
	for (let r = 0; r < rounds; r += 1) {
		const root = fresh(kind);
		const t0 = performance.now();
		const dispose = render(Rows(n, label, (): void => {}), host, root);
		flush();
		const t1 = performance.now();
		setLabel("u" + r.toString());
		flush();
		const t2 = performance.now();
		mountBest = minOf(mountBest, t1 - t0);
		updateBest = minOf(updateBest, t2 - t1);
		dispose();
	}
	line(`compiled-${kind} mount`, mountBest, n, "");
	line(`compiled-${kind} update`, updateBest, n, "");
}

function guest(interp: Interpreter, name: string, kind: string, local: boolean, styles: boolean, n: int32, rounds: int32): void {
	unboxStyles = styles;
	let mountBest = 1e18;
	let updateBest = 1e18;
	let mountCalls = 0;
	let updateCalls = 0;
	for (let r = 0; r < rounds; r += 1) {
		const root = fresh(kind);
		const rootId = add(root);
		calls = 0;
		const t0 = performance.now();
		call(interp, "mount", [hostValue(boxInt(rootId)), hostValue(boxInt(n)), hostValue(boxBool(local)), hostValue(boxBool(host.paragraph !== null))]);
		const t1 = performance.now();
		mountCalls = calls;
		calls = 0;
		call(interp, "update", []);
		const t2 = performance.now();
		updateCalls = calls;
		mountBest = minOf(mountBest, t1 - t0);
		updateBest = minOf(updateBest, t2 - t1);
	}
	line(`${name} mount`, mountBest, n, ` hostCalls=${mountCalls}`);
	line(`${name} update`, updateBest, n, ` hostCalls=${updateCalls}`);
}

function events(interp: Interpreter, n: int32): void {
	const dispatch = routine(interp, "dispatch");
	const before = unboxInt(call(interp, "pressCount", []).root);
	const t0 = performance.now();
	for (let h = 0; h < n; h += 1) {
		const got = callRoutine(interp, dispatch, [
			hostValue(boxInt(h)), hostValue(boxFloat(1.0)), hostValue(boxFloat(2.0)), hostValue(boxFloat(3.0)),
			hostValue(boxFloat(0.0)), hostValue(boxBool(true)), hostValue(boxBool(false)),
		]);
		if (!got.ok) { throw new Error(got.error); }
	}
	const t1 = performance.now();
	const after = unboxInt(call(interp, "pressCount", []).root);
	console.log(`guest-dispatch calls=${n} seen=${after - before} usPerCall=${((t1 - t0) * 1000.0 / (n as number)).toFixed(3)}`);
}

function interpreter(sandboxed: boolean): Interpreter {
	const made = sandboxed
		? createInterpreter(`${homeDir()}/.metascript`, [], machineSystem())
		: createInterpreter(`${homeDir()}/.metascript`, []);
	if (!made.ok) { throw new Error(made.error); }
	const configured = applyProjectConfig(made.value.opts, realpath("."));
	if (!configured.ok) { throw new Error(configured.error); }
	const t0 = performance.now();
	const ran = evalModule(made.value, "bench/raiserBridge/guest.ms");
	if (!ran.ok) { throw new Error(ran.error.map((d) => `${d.file}:${d.line}: ${d.message}`).join("\n")); }
	console.log(`evalModule sandboxed=${sandboxed} ms=${(performance.now() - t0).toFixed(0)}`);
	return made.value;
}

function main(): void {
	const n = argv.length > 1 ? parseInt(argv[1]) as int32 : 1000;
	const rounds = argv.length > 2 ? parseInt(argv[2]) as int32 : 5;
	compiled("mock", n, rounds);
	compiled("void", n, rounds);
	implement();
	const plain = interpreter(false);
	guest(plain, "vm-local", "mock", true, true, n, rounds);
	guest(plain, "bridge-mock-nostyle", "mock", false, false, n, rounds);
	guest(plain, "bridge-mock", "mock", false, true, n, rounds);
	guest(plain, "bridge-void", "void", false, true, n, rounds);
	events(plain, n);
	const boxed = interpreter(true);
	guest(boxed, "sandboxed-bridge-void", "void", false, true, n, rounds);
}

main();
