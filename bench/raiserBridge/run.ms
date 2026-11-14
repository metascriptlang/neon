import { render, mockHost, mockNode, fireEventWith, MockNode, Host, HostNode } from "../../src/render/host";
import { neonEvent, eventType } from "../../src/render/event";
import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
import { Dispose } from "../../src/core/types";
import { createVoidHost, VoidHost } from "../../src/platform/void/host";
import {
	GuestProgram, GuestSlot, RaiserHostValue, openGuest, loadGuest, callGuest, hostValue, boxInt, unboxInt,
} from "../../src/platform/raiser/native";
import { Rows } from "./rows";
import { argv } from "std/process";
import { machineSystem } from "../../../recompiler/src/embed/index";

let host: Host = mockHost();

function minOf(a: number, b: number): number { return a < b ? a : b; }

function fresh(kind: string): HostNode {
	if (kind === "void") {
		const vh: VoidHost = createVoidHost();
		host = vh.host;
		return vh.root as unknown as HostNode;
	}
	host = mockHost();
	return mockNode("root") as unknown as HostNode;
}

function line(name: string, ms: number, n: int32): void {
	console.log(`${name} N=${n} ms=${ms.toFixed(3)} usPerRow=${(ms * 1000.0 / (n as number)).toFixed(2)}`);
}

function call(p: GuestProgram, name: string, args: RaiserHostValue[]): RaiserHostValue {
	const got = callGuest(p, name, args);
	if (!got.ok) { throw new Error(`${name}: ${got.error}`); }
	return got.value;
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
	line(`compiled-${kind} mount`, mountBest, n);
	line(`compiled-${kind} update`, updateBest, n);
}

function local(p: GuestProgram, n: int32, rounds: int32): void {
	let mountBest = 1e18;
	let updateBest = 1e18;
	for (let r = 0; r < rounds; r += 1) {
		const t0 = performance.now();
		call(p, "mountLocal", [hostValue(boxInt(n))]);
		const t1 = performance.now();
		call(p, "update", []);
		const t2 = performance.now();
		mountBest = minOf(mountBest, t1 - t0);
		updateBest = minOf(updateBest, t2 - t1);
	}
	line("vm-local mount", mountBest, n);
	line("vm-local update", updateBest, n);
	call(p, "unmountLocal", []);
}

function bridged(p: GuestProgram, name: string, kind: string, n: int32, rounds: int32, last: (root: HostNode) => void): void {
	let mountBest = 1e18;
	let updateBest = 1e18;
	for (let r = 0; r < rounds; r += 1) {
		const root = fresh(kind);
		const t0 = performance.now();
		const dispose = createRoot((d: Dispose): Dispose => {
			render(GuestSlot({ program: p, view: "rows", args: [hostValue(boxInt(n))] }), host, root);
			return d;
		});
		flush();
		const t1 = performance.now();
		call(p, "update", []);
		flush();
		const t2 = performance.now();
		mountBest = minOf(mountBest, t1 - t0);
		updateBest = minOf(updateBest, t2 - t1);
		if (r + 1 === rounds) { last(root); }
		dispose();
	}
	line(`${name} mount`, mountBest, n);
	line(`${name} update`, updateBest, n);
}

function nothing(root: HostNode): void {}

function pressables(n: MockNode, out: MockNode[]): void {
	if (n.tag === "pressable") { out.push(n); }
	for (const child of n.children) { pressables(child, out); }
}

function presses(p: GuestProgram, root: HostNode): void {
	const targets: MockNode[] = [];
	pressables(root as unknown as MockNode, targets);
	const before = unboxInt(call(p, "pressCount", []).root);
	const t0 = performance.now();
	for (const target of targets) { fireEventWith(target, "onPress", neonEvent(eventType("onPress"))); }
	const t1 = performance.now();
	const seen = unboxInt(call(p, "pressCount", []).root) - before;
	const each = (t1 - t0) * 1000.0 / (targets.length as number);
	console.log(`bridge-press events=${targets.length} seen=${seen} usPerEvent=${each.toFixed(3)}`);
}

function program(sandboxed: boolean): GuestProgram {
	const opened = openGuest(".", sandboxed ? machineSystem() : null);
	if (!opened.ok) { throw new Error(opened.error); }
	const t0 = performance.now();
	const loaded = loadGuest(opened.value, "bench/raiserBridge/guest.ms");
	if (!loaded.ok) { throw new Error(loaded.error.map((d) => `${d.file}:${d.line}: ${d.message}`).join("\n")); }
	console.log(`evalModule sandboxed=${sandboxed} ms=${(performance.now() - t0).toFixed(0)}`);
	return opened.value;
}

function main(): void {
	const n = argv.length > 1 ? parseInt(argv[1]) as int32 : 1000;
	const rounds = argv.length > 2 ? parseInt(argv[2]) as int32 : 5;
	compiled("mock", n, rounds);
	compiled("void", n, rounds);
	const plain = program(false);
	local(plain, n, rounds);
	bridged(plain, "bridge-mock", "mock", n, rounds, (root: HostNode): void => { presses(plain, root); });
	bridged(plain, "bridge-void", "void", n, rounds, nothing);
	const boxed = program(true);
	bridged(boxed, "sandboxed-bridge-void", "void", n, rounds, nothing);
}

main();
