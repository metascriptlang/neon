import { createContext, useContext } from "../src/render/context";
import { accessor } from "../src/core/signal";
import { Host, HostNode, NeonNode } from "../src/render/hostTypes";
import { MockNode, mockNode, mockHost, render } from "../src/render/host";

let sink: number = 0;

function mountRows(n: number): number {
	const T = createContext<number>(0);
	const consumer: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => { sink += useContext(T); };
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		for (let i = 0; i < n; i += 1) {
			const v = i;
			T.Provider({ value: accessor((): number => v), children: consumer })(host, parent, before);
		}
	};
	const root: MockNode = mockNode("root");
	const t0 = performance.now();
	render(app, mockHost(), root as unknown as HostNode);
	return performance.now() - t0;
}

for (const n of [500, 1000, 2000, 4000, 8000]) {
	console.log(`rows=${n} mount_us=${Math.round(mountRows(n) * 1000)}`);
}
console.log(`sink=${sink}`);
