import { render, mockHost } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { Dispose } from "../../src/core/types";
import { mountGuest } from "../../src/platform/raiser/guest";
import { Rows } from "./rows";
import { NeonNode } from "../../src/render/hostTypes";

export { raiserDispatch, raiserDispose } from "../../src/platform/raiser/guest";

const [label, setLabel] = createSignal("a");
let presses: int32 = 0;
let tick: int32 = 0;
let local: Dispose | null = null;

function pressed(): void {
	presses += 1;
}

export function rows(root: int32, n: int32): void {
	mountGuest(root, (): NeonNode => Rows(n, label, pressed));
}

export function mountLocal(n: int32): void {
	const d = local;
	if (d !== null) { d(); }
	const host = mockHost();
	local = render(Rows(n, label, pressed), host, host.createElement("root"));
	flush();
}

export function unmountLocal(): void {
	const d = local;
	local = null;
	if (d !== null) { d(); }
}

export function update(): void {
	tick += 1;
	setLabel("v" + tick.toString());
	flush();
}

export function pressCount(): int32 {
	return presses;
}
