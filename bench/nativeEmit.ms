import { createSignal } from "../src/core/signal";
import { element } from "../src/macros/ui/element";
import { direct } from "../src/macros/ui/direct";
import { renderToHost, renderNode, mockHost, Host, HostNode } from "../src/render/host";
import { createVoidHost, VoidHost } from "../src/platform/void/host";

function nativeHost(): Host {
	const h = mockHost();
	return {
		createElement: h.createElement,
		createText: h.createText,
		setText: h.setText,
		setAttr: h.setAttr,
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

function tree0(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		renderNode(element(<div class="row"><span class="c">a</span><span class="c">b</span><span class="c">c</span><span class="c">d</span><span class="c">e</span><span class="c">f</span></div>), host);
		i = i + 1;
	}
}

function directSite0(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		const m = direct(<div class="row"><span class="c">a</span><span class="c">b</span><span class="c">c</span><span class="c">d</span><span class="c">e</span><span class="c">f</span></div>);
		m(host);
		i = i + 1;
	}
}

function tree3(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		renderNode(element(<div class="row"><span class="c">{sig()}</span><span class="c">b</span><span class="c">{sig()}</span><span class="c">d</span><span class="c">{sig()}</span><span class="c">f</span></div>), host);
		i = i + 1;
	}
}

function directSite3(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		const m = direct(<div class="row"><span class="c">{sig()}</span><span class="c">b</span><span class="c">{sig()}</span><span class="c">d</span><span class="c">{sig()}</span><span class="c">f</span></div>);
		m(host);
		i = i + 1;
	}
}

function tree6(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		renderNode(element(<div class="row"><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span></div>), host);
		i = i + 1;
	}
}

function directSite6(host: Host, sig: () => string): void {
	let i = 0;
	while (i < N) {
		const m = direct(<div class="row"><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span><span class="c">{sig()}</span></div>);
		m(host);
		i = i + 1;
	}
}

function voidTree3(vh: VoidHost, sig: () => string): void {
	const root = vh.root as unknown as HostNode;
	let i = 0;
	while (i < N) {
		renderToHost(element(<div class="row"><span class="c">{sig()}</span><span class="c">b</span><span class="c">{sig()}</span><span class="c">d</span><span class="c">{sig()}</span><span class="c">f</span></div>), vh.host, root);
		i = i + 1;
	}
}

function voidDirect3(vh: VoidHost, sig: () => string): void {
	const root = vh.root as unknown as HostNode;
	let i = 0;
	while (i < N) {
		const m = direct(<div class="row"><span class="c">{sig()}</span><span class="c">b</span><span class="c">{sig()}</span><span class="c">d</span><span class="c">{sig()}</span><span class="c">f</span></div>);
		vh.host.append(root, m(vh.host));
		i = i + 1;
	}
}

function timeTree0(sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const h = nativeHost();
		const t0 = performance.now();
		tree0(h, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function timeDirect0(sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const h = nativeHost();
		const t0 = performance.now();
		directSite0(h, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function timeTree3(sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const h = nativeHost();
		const t0 = performance.now();
		tree3(h, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function timeDirect3(sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const h = nativeHost();
		const t0 = performance.now();
		directSite3(h, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function timeTree6(sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const h = nativeHost();
		const t0 = performance.now();
		tree6(h, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function timeDirect6(sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const h = nativeHost();
		const t0 = performance.now();
		directSite6(h, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function timeVoidTree3(sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const vh = createVoidHost();
		const t0 = performance.now();
		voidTree3(vh, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function timeVoidDirect3(sig: () => string): number {
	let best = 1e18;
	let r = 0;
	while (r < ROUNDS) {
		const vh = createVoidHost();
		const t0 = performance.now();
		voidDirect3(vh, sig);
		best = minOf(best, performance.now() - t0);
		r = r + 1;
	}
	return best;
}

function main(): void {
	const [sig, setSig] = createSignal("v");
	console.log("BENCH-BEGIN");
	console.log("N=" + N.toString() + " rounds=" + ROUNDS.toString() + " (min of rounds, ms)");

	const t0 = timeTree0(sig);
	const d0 = timeDirect0(sig);
	console.log("dyn0   tree=" + t0.toString() + "  direct=" + d0.toString() + "  ratio=" + (t0 / d0).toString());

	const t3 = timeTree3(sig);
	const d3 = timeDirect3(sig);
	console.log("dyn3   tree=" + t3.toString() + "  direct=" + d3.toString() + "  ratio=" + (t3 / d3).toString());

	const t6 = timeTree6(sig);
	const d6 = timeDirect6(sig);
	console.log("dyn6   tree=" + t6.toString() + "  direct=" + d6.toString() + "  ratio=" + (t6 / d6).toString());

	const v3 = timeVoidTree3(sig);
	const vd3 = timeVoidDirect3(sig);
	console.log("void3  tree=" + v3.toString() + "  direct=" + vd3.toString() + "  ratio=" + (v3 / vd3).toString());

	console.log("BENCH-END");
}

main();
