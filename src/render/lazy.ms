import { createAsyncMemo } from "../core/memo";
import { accessor } from "../core/signal";
import { getOwner } from "../core/runtime";
import { serverContext } from "../core/serverContext";
import { Host, HostNode, NeonNode } from "./hostTypes";
import { createComponent } from "./component";
import { moduleKeys } from "./hydrationRecords";
import { Show } from "../macros/ui/flow";

class LazyModule<P> {
	load: () => Promise<(props: P) => NeonNode>;
	loading: Promise<boolean>[] = [];
	loaded: ((props: P) => NeonNode)[] = [];

	constructor(load: () => Promise<(props: P) => NeonNode>) {
		this.load = load;
	}
}

interface LazyEntry {
	state: unknown;
	start: () => Promise<boolean>;
	loaded: () => boolean;
}

const lazyEntries = new Map<string, LazyEntry>();

function startLoad<P>(m: LazyModule<P>): Promise<boolean> {
	if (m.loading.length === 0) {
		const current = m.load().then((comp): boolean => { m.loaded.push(comp); return true; });
		m.loading.push(current);
		current.catch((e): boolean => { if (m.loading.length > 0 && m.loading[0] === current) { m.loading.pop(); } return false; });
	}
	return m.loading[0];
}

function entryFor<P>(key: string, load: () => Promise<(props: P) => NeonNode>): LazyModule<P> {
	const known = lazyEntries.get(key);
	if (known !== null) {
		const state = known.state as LazyModule<P>;
		if (state.load !== load) {
			throw new Error("[LAZY_DUPLICATE_KEY] two different loads are registered under the lazy module key \"" + key + "\": a key names one module");
		}
		return state;
	}
	const fresh = new LazyModule<P>(load);
	lazyEntries.set(key, { state: fresh as unknown, start: (): Promise<boolean> => startLoad<P>(fresh), loaded: (): boolean => fresh.loaded.length > 0 });
	return fresh;
}

// Parked on ~/metascript/.inbox/compiler/2026-09-24-default-import-does-not-parse.md, 2026-10-16-promise-or-null-is-never-null-on-c-and-js.md and 2026-10-24-design-a-property-assigned-onto-a-function-value.md: Solid's `lazy(() => import("./Page"))` reading the default export, one `Promise | null` slot for the load, and `.preload()` on the component.
export function lazyModule<P>(key: string, load: () => Promise<(props: P) => NeonNode>): (props: P) => NeonNode {
	const m = entryFor<P>(key, load);
	return (props: P): NeonNode => (host: Host, parent: HostNode, before: HostNode | null): void => {
		const mount: NeonNode = (h: Host, p: HostNode, b: HostNode | null): void => { createComponent(m.loaded[0], props)(h, p, b); };
		const ready = createAsyncMemo((prev: boolean | null): Promise<boolean> => {
			const ctx = serverContext();
			const self = getOwner();
			if (ctx !== null && self !== null && self.id !== null) { ctx.modules.set(self.id as string, key); }
			return startLoad<P>(m);
		});
		Show({ when: accessor((): boolean => m.loaded.length > 0 || ready()), children: mount })(host, parent, before);
	};
}

export function preloadLazy(keys: string[]): Promise<void> {
	const waits: Promise<boolean>[] = [];
	for (const key of keys) {
		const entry = lazyEntries.get(key);
		if (entry === null) {
			throw new Error("[LAZY_UNREGISTERED] the page lists the lazy module \"" + key + "\" but this client never created a lazy under that key");
		}
		waits.push(entry.start());
	}
	return settled(waits);
}

async function settled(waits: Promise<boolean>[]): Promise<void> {
	for (const wait of waits) { await wait; }
}

export function lazyLoaded(keys: string[]): boolean {
	for (const key of keys) {
		const entry = lazyEntries.get(key);
		if (entry === null || !entry.loaded()) { return false; }
	}
	return true;
}

export function preloadServedLazy(): Promise<void> {
	return preloadLazy(moduleKeys());
}
