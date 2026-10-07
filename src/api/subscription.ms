import { Accessor } from "../core/signal";
import { createRoot } from "../core/owner";
import { createEffect } from "../core/effect";
import { untrack } from "../core/signal";

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
		let first = true;
		createEffect((): void => {
			const value = source();
			if (first) {
				first = false;
				return;
			}
			untrack((): void => { changed(value); });
		});
		return { remove: dispose };
	});
}
