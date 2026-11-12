import { requestInputFrame, cancelFrame } from "../../animation/frame";

export struct DesktopPointer {
	kind: "motion" | "wheel";
	x: float32;
	y: float32;
	dx: float32;
	dy: float32;
}

export class DesktopInput {
	queued: DesktopPointer[] = [];
	frame: int32 = 0;
	deliver: (event: DesktopPointer) => void;

	constructor(deliver: (event: DesktopPointer) => void) {
		this.deliver = deliver;
	}

	push(event: DesktopPointer): void {
		const count = this.queued.length;
		if (count > 0 && this.queued[count - 1].kind === event.kind) {
			const last = this.queued[count - 1];
			this.queued[count - 1] = event.kind === "motion" ? event :
				{ ...event, dx: last.dx + event.dx, dy: last.dy + event.dy };
			return;
		}
		this.queued.push(event);
		if (count === 0) {
			this.frame = requestInputFrame((time: number): void => { this.drain(); });
		}
	}

	drain(): void {
		const due = this.queued;
		this.stop();
		for (const event of due) { this.deliver(event); }
	}

	stop(): void {
		this.queued = [];
		cancelFrame(this.frame);
	}
}
