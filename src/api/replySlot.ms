import { sleepAsync } from "std/core/promise";

// Polls instead of settling a `new Promise`, which does not lower (compiler card
// 2026-10-07-new-promise-executor-does-not-lower.md, WORKAROUND P2).
export class TextSlot {
	settled: boolean = false;
	value: string = "";

	settle(value: string): void {
		if (this.settled) { return; }
		this.value = value;
		this.settled = true;
	}

	async wait(): Promise<string> {
		while (!this.settled) { await sleepAsync(16); }
		return this.value;
	}
}
