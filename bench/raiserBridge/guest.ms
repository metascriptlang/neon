import { render, mockHost, HostNode } from "../../src/render/host";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { Dispose } from "../../src/core/types";
import { Rows } from "./rows";
import { bridgeHost, remoteOf, handlerCount } from "./guestHost";

const [label, setLabel] = createSignal("a");
let presses: int32 = 0;
let tick: int32 = 0;
let dispose: Dispose | null = null;

export function mount(root: int32, n: int32, local: boolean, paragraphs: boolean): void {
	const d = dispose;
	if (d !== null) { d(); }
	const host = local ? mockHost() : bridgeHost(paragraphs);
	const parent = local ? host.createElement("root") : remoteOf(root) as HostNode;
	dispose = render(Rows(n, label, (): void => { presses += 1; }), host, parent);
	flush();
}

export function update(): void {
	tick += 1;
	setLabel("v" + tick.toString());
	flush();
}

export function handlers(): int32 {
	return handlerCount();
}

export function dispatch(handler: int32, x: number, y: number, timeStamp: number, button: number, pressed: boolean, pointerOrigin: boolean): void {
	if (handler >= 0 && pressed && !pointerOrigin) { presses += 1; }
}

export function pressCount(): int32 {
	return presses;
}
