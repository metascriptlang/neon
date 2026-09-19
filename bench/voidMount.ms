import { createSignal, Accessor } from "../src/core/signal";
import { NeonNode } from "../src/render/node";
import { render, HostNode } from "../src/render/host";
import { For } from "../src/macros/ui/flow";
import { createVoidHost, VoidHost } from "../src/platform/void/host";
import { argv } from "std/process";

function minOf(a: number, b: number): number { return a < b ? a : b; }

function range(n: number): number[] {
	const out: number[] = [];
	for (let i = 0; i < n; i += 1) { out.push(i as number); }
	return out;
}

function appendRows(vh: VoidHost, n: number, sig: () => string): void {
	const root = vh.root as unknown as HostNode;
	for (let i = 0; i < n; i += 1) {
		const node: NeonNode = <div class="row"><span class="c">{sig()}</span><span class="c">b</span><span class="c">{sig()}</span><span class="c">d</span><span class="c">{sig()}</span><span class="c">f</span></div>;
		node(vh.host, root, null);
	}
}

function forRows(vh: VoidHost, n: number, sig: () => string): void {
	const [items, setItems] = createSignal<number[]>(range(n));
	render(<div><For each={items()}>{(item: number, ix: Accessor<number>): NeonNode => <div class="row"><span class="c">{sig()}</span><span class="c">b</span><span class="c">{sig()}</span><span class="c">d</span><span class="c">{sig()}</span><span class="c">f</span></div>}</For></div>, vh.host, vh.root as unknown as HostNode);
}

function usPerRow(cell: string, n: number, rounds: number, sig: () => string): number {
	let best = 1e18;
	for (let r = 0; r < rounds; r += 1) {
		const vh = createVoidHost();
		const t0 = performance.now();
		if (cell === "for") { forRows(vh, n, sig); } else { appendRows(vh, n, sig); }
		best = minOf(best, performance.now() - t0);
	}
	return best * 1000.0 / n;
}

function main(): void {
	const [sig, setSig] = createSignal("v");
	if (argv.length > 3) {
		const cell = argv[1];
		const n = parseInt(argv[2]) as number;
		const rounds = parseInt(argv[3]) as number;
		console.log("void " + cell + " N=" + n.toString() + " rounds=" + rounds.toString() + " usPerRow=" + usPerRow(cell, n, rounds, sig).toString());
		return;
	}
	for (const n of [1000, 5000, 20000]) {
		console.log("void append N=" + n.toString() + " usPerRow=" + usPerRow("append", n, n > 5000 ? 1 : 3, sig).toString());
	}
}

main();
