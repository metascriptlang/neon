import { Dispose } from "../core/types";
import { getOwner } from "../core/runtime";
import { onCleanup } from "../core/cleanup";
import { RoutingError, RoutingRegistry, RoutingSnapshot } from "./routing";

export struct RoutingHistoryEntry {
	url: string;
	state: string;
}

export interface RoutingHistory {
	writable: boolean;
	read: () => RoutingHistoryEntry;
	push: (entry: RoutingHistoryEntry) => void;
	replace: (entry: RoutingHistoryEntry) => void;
	go: (delta: int32) => boolean;
	listen: (listener: (entry: RoutingHistoryEntry) => void) => Dispose;
}

interface HistoryListener {
	id: int32;
	callback: (entry: RoutingHistoryEntry) => void;
}

export function createMemoryRoutingHistory(initial: RoutingHistoryEntry): RoutingHistory {
	let entries: RoutingHistoryEntry[] = [{ url: initial.url, state: initial.state }];
	let index: int32 = 0;
	let listeners: HistoryListener[] = [];
	let nextId: int32 = 0;
	const read = (): RoutingHistoryEntry => {
		return { url: entries[index].url, state: entries[index].state };
	};
	return {
		writable: true,
		read,
		push: (entry: RoutingHistoryEntry): void => {
			entries = entries.slice(0, index + 1);
			entries.push({ url: entry.url, state: entry.state });
			index += 1;
		},
		replace: (entry: RoutingHistoryEntry): void => {
			entries[index] = { url: entry.url, state: entry.state };
		},
		go: (delta: int32): boolean => {
			const next = index + delta;
			if (next < 0 || next >= entries.length || next === index) { return false; }
			index = next;
			const entry = read();
			for (const listener of listeners.slice(0)) { listener.callback(entry); }
			return true;
		},
		listen: (listener: (entry: RoutingHistoryEntry) => void): Dispose => {
			const id = nextId;
			nextId += 1;
			listeners.push({ id, callback: listener });
			let removed = false;
			return (): void => {
				if (removed) { return; }
				removed = true;
				const kept: HistoryListener[] = [];
				for (const current of listeners) {
					if (current.id !== id) { kept.push(current); }
				}
				listeners = kept;
			};
		},
	};
}

export function createRequestRoutingHistory(url: string): RoutingHistory {
	const refuse = (): void => { throw new Error("routing: request history is read-only"); };
	return {
		writable: false,
		read: (): RoutingHistoryEntry => ({ url, state: "" }),
		push: (entry: RoutingHistoryEntry): void => refuse(),
		replace: (entry: RoutingHistoryEntry): void => refuse(),
		go: (delta: int32): boolean => { refuse(); return false; },
		listen: (listener: (entry: RoutingHistoryEntry) => void): Dispose => (): void => {},
	};
}

function restoreEntry(
	registry: RoutingRegistry,
	entry: RoutingHistoryEntry,
): Result<void, RoutingError> {
	if (entry.state === "") { return registry.apply(entry.url); }
	const decoded = JSON.parse<RoutingSnapshot>(entry.state);
	if (!decoded.ok) { return Result.err(RoutingError.IncompleteSnapshot); }
	return registry.restore(decoded.value);
}

export class RoutingSession {
	private registry: RoutingRegistry;
	private history: RoutingHistory;
	private unsubscribe: Dispose;
	private disposed: boolean = false;
	private previous: RoutingHistoryEntry;

	constructor(
		registry: RoutingRegistry,
		history: RoutingHistory,
		onError: (error: RoutingError) => void,
	) {
		this.registry = registry;
		this.history = history;
		this.previous = history.read();
		this.unsubscribe = history.listen((entry: RoutingHistoryEntry): void => {
			const restored = restoreEntry(this.registry, entry);
			if (!restored.ok) {
				if (this.history.writable) { this.history.replace(this.previous); }
				onError(restored.error);
				return;
			}
			this.previous = entry;
			const landed = this.registry.address();
			if (this.history.writable && landed.ok && landed.value !== entry.url) { this.sync(true); }
		});
	}

	navigate(url: string, replace: boolean): Result<void, RoutingError> {
		this.checkWritable();
		const before = this.registry.capture();
		const applied = try this.registry.apply(url);
		const synced = this.sync(replace);
		if (!synced.ok) {
			const restored = this.registry.restore(before);
			if (!restored.ok) {
				throw new Error("routing: failed to restore after address failure");
			}
		}
		return synced;
	}

	sync(replace: boolean): Result<void, RoutingError> {
		this.checkWritable();
		const url = try this.registry.address();
		const entry: RoutingHistoryEntry = {
			url,
			state: JSON.stringify(this.registry.capture()),
		};
		if (replace) { this.history.replace(entry); }
		else { this.history.push(entry); }
		this.previous = entry;
		return Result.ok(null);
	}

	dispose(): void {
		if (this.disposed) { return; }
		this.disposed = true;
		this.unsubscribe();
	}

	private checkWritable(): void {
		if (this.disposed) { throw new Error("routing: session is disposed"); }
		if (!this.history.writable) { throw new Error("routing: request history is read-only"); }
	}
}

export function createRoutingSession(
	registry: RoutingRegistry,
	history: RoutingHistory,
	onError: (error: RoutingError) => void,
): Result<RoutingSession, RoutingError> {
	const initialized = try restoreEntry(registry, history.read());
	const session = new RoutingSession(registry, history, onError);
	if (history.writable) {
		const synced = session.sync(true);
		if (!synced.ok) { session.dispose(); return Result.err(synced.error); }
	}
	if (getOwner() !== null) { onCleanup((): void => session.dispose()); }
	return Result.ok(session);
}
