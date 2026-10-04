import { createContext, useContext, Context } from "../src/render/context";
import { accessor } from "../src/core/signal";
import { Host, HostNode, NeonNode } from "../src/render/hostTypes";
import { MockNode, mockNode, mockHost, render } from "../src/render/host";
import { createRoot } from "../src/core/owner";
import { Dispose } from "../src/core/types";

let sink: number = 0;
let readNs: number = 0;

const READS = 200000;

function chain(B: Context<number>, depth: number, leaf: NeonNode): NeonNode {
	let node = leaf;
	for (let d = 0; d < depth; d += 1) {
		const inner = node;
		node = B.Provider({ value: accessor((): number => 1), children: inner });
	}
	return node;
}

function roots(depth: number, leaf: NeonNode): NeonNode {
	let node = leaf;
	for (let d = 0; d < depth; d += 1) {
		const inner = node;
		node = (host: Host, parent: HostNode, before: HostNode | null): void => {
			createRoot((dispose: Dispose): number => { inner(host, parent, before); return 0; });
		};
	}
	return node;
}

function measure(depth: number, providers: boolean): number {
	const A = createContext<number>(0);
	const B = createContext<number>(0);
	const consumer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const t0 = performance.now();
		for (let i = 0; i < READS; i += 1) { sink += useContext(A); }
		readNs = (performance.now() - t0) * 1000000 / READS;
	};
	const app: NeonNode = A.Provider({ value: accessor((): number => 7), children: providers ? chain(B, depth, consumer) : roots(depth, consumer) });
	const root: MockNode = mockNode("root");
	render(app, mockHost(), root as unknown as HostNode);
	return readNs;
}

for (const depth of [0, 10, 50, 200]) {
	console.log(`owners between=${depth} read_ns=${Math.round(measure(depth, false) * 100) / 100}`);
}
for (const depth of [0, 10, 50, 200]) {
	console.log(`providers between=${depth} read_ns=${Math.round(measure(depth, true) * 100) / 100}`);
}
console.log(`sink=${sink}`);
