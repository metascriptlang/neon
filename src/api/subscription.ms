import { Accessor } from "../core/signal";
import { createRoot } from "../core/owner";
import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";

export interface EventSubscription {
	remove: () => void;
}

interface Entry<T> {
	id: int32;
	handler: (value: T) => void;
}

// Keyed by id, not handler identity: comparing function values dies at clang on C
// (compiler card 2026-10-07-function-value-identity-dies-at-clang.md).
export class Listeners<T> {
	private entries: Entry<T>[] = [];
	private nextId: int32 = 1;

	add(handler: (value: T) => void): EventSubscription {
		const id = this.nextId;
		this.nextId += 1;
		this.entries.push({ id, handler });
		return { remove: (): void => { this.removeId(id); } };
	}

	private removeId(id: int32): void {
		for (let i = 0; i < this.entries.length; i += 1) {
			if (this.entries[i].id === id) {
				this.entries.splice(i, 1);
				return;
			}
		}
	}

	emit(value: T): void {
		for (const entry of this.entries.slice(0, this.entries.length)) { entry.handler(value); }
	}

	count(): int32 {
		return this.entries.length as int32;
	}
}

export function onChange<T>(source: Accessor<T>, changed: (value: T) => void): EventSubscription {
	return createRoot((dispose: () => void): EventSubscription => {
		createRenderEffect<T>(
			(prev: T | null): T => source(),
			(value: T, prev: T | null): Cleanup | null => { changed(value); return null; },
			{ defer: true },
		);
		return { remove: dispose };
	});
}
