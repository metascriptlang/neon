import { moduleKeys } from "./hydrationRecords";

export interface LazyEntry {
	state: unknown;
	start: () => Promise<boolean>;
	loaded: () => boolean;
}

export const lazyEntries = new Map<string, LazyEntry>();

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
