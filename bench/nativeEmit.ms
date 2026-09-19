import { createSignal, Accessor } from "../src/core/signal";
import { mockHost, Host, HostNode, NeonNode } from "../src/render/host";
import { createVoidHost, VoidHost } from "../src/platform/void/host";

function nativeHost(): Host {
	const h = mockHost();
	return {
		createElement: h.createElement,
		createText: h.createText,
		setText: h.setText,
		setAttr: h.setAttr,
		removeAttr: h.removeAttr,
		setStyle: h.setStyle,
		setStyleProp: h.setStyleProp,
		setStyleClass: h.setStyleClass,
		addEvent: h.addEvent,
		append: h.append,
		insertBefore: h.insertBefore,
		removeChild: h.removeChild,
		nextSibling: h.nextSibling,
		firstChild: h.firstChild,
		cloneNode: null,
	};
}

const N = 1000;
const ROUNDS = 3;

function minOf(a: number, b: number): number { return a < b ? a : b; }

function mount0(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		const node: NeonNode = <div class="row"><span class="c">a</span><span class="c">b</span><span class="c">c</span><span class="c">d</span><span class="c">e</span><span class="c">f</span></div>;
		node(host, host.createElement("slot"), null);
		i = i + 1;
	}
}

function mount3(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		const node: NeonNode = <div class="row"><span class="c">{sig()}</span><span class="c">b</span><span class="c">{sig()}</span><span class="c">d</span><span class="c">{sig()}</span><span class="c">f</span></div>;
		node(host, host.createElement("slot"), null);
		i = i + 1;
	}
}

function mount6(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		const node: NeonNode = <div class="row"><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span></div>;
		node(host, host.createElement("slot"), null);
		i = i + 1;
	}
}

interface RowProps {
	v: Accessor<string>;
}

function RowC(props: RowProps): NeonNode {
	return <div class="row"><span class="c">{props.v}</span><span class="c">b</span><span class="c">{props.v}</span><span class="c">d</span><span class="c">{props.v}</span><span class="c">f</span></div>;
}

function mountComp3(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		const node: NeonNode = <RowC v={sig()} />;
		node(host, host.createElement("slot"), null);
		i = i + 1;
	}
}

function voidMount3(vh: VoidHost, sig: () => string): void {
	const root = vh.root as unknown as HostNode;
	let i = 0;
	while (i < N) {
		const node: NeonNode = <div class="row"><span class="c">{sig()}</span><span class="c">b</span><span class="c">{sig()}</span><span class="c">d</span><span class="c">{sig()}</span><span class="c">f</span></div>;
		node(vh.host, root, null);
		i = i + 1;
	}
}

function timeOn(makeHost: () => Host, run: (host: Host, sig: () => string) => void, sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const h = makeHost();
		const t0 = performance.now();
		run(h, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function timeVoid3(sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const vh = createVoidHost();
		const t0 = performance.now();
		voidMount3(vh, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function report(label: string, run: (host: Host, sig: () => string) => void, sig: () => string): void {
	const rebuilt = timeOn(nativeHost, run, sig);
	const cloned = timeOn(mockHost, run, sig);
	console.log(label + "  rebuild=" + rebuilt.toString() + "  clone=" + cloned.toString());
}

function main(): void {
	const [sig, setSig] = createSignal("v");
	console.log("BENCH-BEGIN");
	console.log("N=" + N.toString() + " rounds=" + ROUNDS.toString() + " (min of rounds, ms)");
	report("dyn0 ", mount0, sig);
	report("dyn3 ", mount3, sig);
	report("dyn6 ", mount6, sig);
	report("comp3", mountComp3, sig);
	console.log("void3  mount=" + timeVoid3(sig).toString());
	console.log("BENCH-END");
}

main();
