export class TimerHandle {
	private id: int32 | null = null;

	pending(): boolean {
		return this.id !== null;
	}

	cancel(): void {
		const id = this.id;
		if (id === null) { return; }
		this.id = null;
		clearTimeout(id);
	}

	start(callback: () => void, delayMs: number): void {
		this.cancel();
		this.id = setTimeout((): void => {
			this.id = null;
			callback();
		}, delayMs) as int32;
	}
}
