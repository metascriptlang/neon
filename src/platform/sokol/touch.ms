import { AreaKeyMod, AreaPointerKind } from "../../render/voidAreaHandle";
import { DOM_DELTA_PIXEL } from "../../render/event";
import { WindowArea, deliverPointer } from "../void/windowHost";
import { AppEventType, AppTouch } from "../../../../void/src/sokol/window";
import { requestFrame, cancelFrame, frameNow } from "../../animation/frame";

// Flutter's touch gestures on iOS: gestures/constants.dart, BouncingScrollPhysics and
// IOSScrollViewFlingVelocityTracker. Change a value there first, then here.
const TOUCH_SLOP = 18.0;
const PAN_SLOP = 36.0;
const LONG_PRESS_MS = 500.0;
const MIN_FLING_VELOCITY = 100.0;
const MIN_FLING_DISTANCE = 18.0;
const MAX_FLING_VELOCITY = 8000.0;
const FRICTION_DRAG = 0.135;
const FLING_SAMPLES: int32 = 20;
const POINTER_STOPPED_MS = 40.0;

struct Offset {
	x: float64;
	y: float64;
}

struct VelocityEstimate {
	velocity: Offset;
	offset: Offset;
}

function wrapSample(i: int32): int32 {
	return ((i % FLING_SAMPLES) + FLING_SAMPLES) % FLING_SAMPLES;
}

class FlingTracker {
	times: float64[] = [];
	points: Offset[] = [];
	filled: boolean[] = [];
	index: int32 = 0;
	last: float64 = 0.0;

	constructor() {
		for (let i = 0; i < FLING_SAMPLES; i += 1) {
			this.times.push(0.0);
			this.points.push({ x: 0.0, y: 0.0 });
			this.filled.push(false);
		}
	}

	add(time: float64, at: Offset): void {
		this.last = time;
		this.index = wrapSample(this.index + 1);
		this.times[this.index] = time;
		this.points[this.index] = at;
		this.filled[this.index] = true;
	}

	velocityAt(back: int32): Offset {
		const end = wrapSample(this.index + back);
		const start = wrapSample(this.index + back - 1);
		if (!this.filled[end] || !this.filled[start]) { return { x: 0.0, y: 0.0 }; }
		const dt = this.times[end] - this.times[start];
		if (dt <= 0.0) { return { x: 0.0, y: 0.0 }; }
		return {
			x: (this.points[end].x - this.points[start].x) * 1000.0 / dt,
			y: (this.points[end].y - this.points[start].y) * 1000.0 / dt,
		};
	}

	estimate(now: float64): VelocityEstimate {
		if (now - this.last > POINTER_STOPPED_MS) {
			return { velocity: { x: 0.0, y: 0.0 }, offset: { x: 0.0, y: 0.0 } };
		}
		const a = this.velocityAt(-2 as int32);
		const b = this.velocityAt(-1 as int32);
		const c = this.velocityAt(0 as int32);
		let oldest = this.index;
		for (let i = 1; i <= FLING_SAMPLES; i += 1) {
			const at = wrapSample(this.index + i);
			if (this.filled[at]) {
				oldest = at;
				break;
			}
		}
		return {
			velocity: { x: a.x * 0.6 + b.x * 0.35 + c.x * 0.05, y: a.y * 0.6 + b.y * 0.35 + c.y * 0.05 },
			offset: { x: this.points[this.index].x - this.points[oldest].x, y: this.points[this.index].y - this.points[oldest].y },
		};
	}
}

class Finger {
	id: int64;
	pixelX: float64;
	pixelY: float64;
	tracker: FlingTracker = new FlingTracker();

	constructor(id: int64, pixelX: float64, pixelY: float64) {
		this.id = id;
		this.pixelX = pixelX;
		this.pixelY = pixelY;
	}
}

enum TouchPhase {
	Idle,
	Pending,
	Pressing,
	Panning,
	Spent,
}

function flingVelocity(e: VelocityEstimate): Offset | null {
	const speed = Math.sqrt(e.velocity.x * e.velocity.x + e.velocity.y * e.velocity.y);
	const travelled = e.offset.x * e.offset.x + e.offset.y * e.offset.y;
	if (speed <= MIN_FLING_VELOCITY || travelled <= MIN_FLING_DISTANCE * MIN_FLING_DISTANCE) { return null; }
	const scale = speed > MAX_FLING_VELOCITY ? MAX_FLING_VELOCITY / speed : 1.0;
	return { x: e.velocity.x * scale, y: e.velocity.y * scale };
}

function frictionAt(velocity: float64, seconds: float64): float64 {
	return velocity * (Math.pow(FRICTION_DRAG, seconds) - 1.0) / Math.log(FRICTION_DRAG);
}

export class TouchGesture {
	area: WindowArea;
	phase: TouchPhase = TouchPhase.Idle;
	fingers: Finger[] = [];
	primary: int64 = 0 as int64;
	tapAlive: boolean = false;
	originX: float64 = 0.0;
	originY: float64 = 0.0;
	downAt: float64 = 0.0;
	travelled: float64 = 0.0;
	mods: BitSet<AreaKeyMod> = 0 as BitSet<AreaKeyMod>;
	deadline: int32 = -1;
	momentum: int32 = -1;
	fling: Offset = { x: 0.0, y: 0.0 };
	flingStart: float64 = -1.0;
	flung: Offset = { x: 0.0, y: 0.0 };
	flingDoneX: boolean = false;
	flingDoneY: boolean = false;

	constructor(area: WindowArea) {
		this.area = area;
	}

	deliver(type: AppEventType, touches: AppTouch[], mods: BitSet<AreaKeyMod>): void {
		this.mods = mods;
		match (type) {
			AppEventType.TouchesBegan => {
				for (const t of touches) {
					if (t.changed) { this.began(t); }
				}
			},
			AppEventType.TouchesMoved => { this.moved(touches); },
			AppEventType.TouchesEnded | AppEventType.TouchesCancelled => {
				for (const t of touches) {
					if (t.changed) { this.ended(t, type === AppEventType.TouchesCancelled); }
				}
			},
			_ => { throw new Error(`sokol touch: ${type.toString()} is not a touch event`); },
		}
	}

	logical(pixelX: float64, pixelY: float64): Offset {
		const scale = this.area.scale as float64;
		return { x: pixelX / scale, y: pixelY / scale };
	}

	finger(id: int64, what: string): Finger {
		for (const f of this.fingers) {
			if (f.id === id) { return f; }
		}
		throw new Error(`sokol touch: touch ${id} ${what} but never began`);
	}

	began(t: AppTouch): void {
		for (const f of this.fingers) {
			if (f.id === t.id) { throw new Error(`sokol touch: touch ${t.id} began twice`); }
		}
		const now = frameNow() as float64;
		const f = new Finger(t.id, t.x as float64, t.y as float64);
		f.tracker.add(now, this.logical(f.pixelX, f.pixelY));
		this.fingers.push(f);
		if (this.phase !== TouchPhase.Idle) { return; }
		const stoppedMomentum = this.stopMomentum();
		this.phase = TouchPhase.Pending;
		this.primary = f.id;
		this.tapAlive = !stoppedMomentum;
		this.originX = f.pixelX;
		this.originY = f.pixelY;
		this.downAt = now;
		this.travelled = 0.0;
		if (this.tapAlive) { this.watchDeadline(); }
	}

	moved(touches: AppTouch[]): void {
		const now = frameNow() as float64;
		const count = this.fingers.length as float64;
		let panX = 0.0;
		let panY = 0.0;
		for (const t of touches) {
			if (!t.changed) { continue; }
			const f = this.finger(t.id, "moved");
			const dx = (t.x as float64) - f.pixelX;
			const dy = (t.y as float64) - f.pixelY;
			f.pixelX = t.x as float64;
			f.pixelY = t.y as float64;
			f.tracker.add(now, this.logical(f.pixelX, f.pixelY));
			const step = this.logical(dx, dy);
			match (this.phase) {
				TouchPhase.Pending => {
					this.travelled += Math.sqrt(step.x * step.x + step.y * step.y);
					const from = this.logical(f.pixelX - this.originX, f.pixelY - this.originY);
					if (this.tapAlive && f.id === this.primary && Math.sqrt(from.x * from.x + from.y * from.y) > TOUCH_SLOP) {
						this.dropTap();
					}
					if (this.travelled > PAN_SLOP) {
						this.dropTap();
						this.phase = TouchPhase.Panning;
					}
				},
				TouchPhase.Pressing => {
					if (f.id === this.primary) { this.pointer(AreaPointerKind.Motion, f.pixelX, f.pixelY, false, dx, dy); }
				},
				TouchPhase.Panning => {
					panX += step.x;
					panY += step.y;
				},
				TouchPhase.Spent => {},
				TouchPhase.Idle => { throw new Error(`sokol touch: touch ${t.id} moved while no touch was down`); },
			}
		}
		if (this.phase === TouchPhase.Panning && (panX !== 0.0 || panY !== 0.0)) { this.wheel(panX / count, panY / count); }
	}

	ended(t: AppTouch, cancelled: boolean): void {
		const f = this.finger(t.id, cancelled ? "was cancelled" : "ended");
		this.fingers.splice(this.fingers.indexOf(f), 1);
		const x = t.x as float64;
		const y = t.y as float64;
		const last = this.fingers.length === 0;
		match (this.phase) {
			TouchPhase.Pending => {
				if (this.tapAlive && f.id === this.primary) {
					this.dropTap();
					if (!cancelled) {
						this.pointer(AreaPointerKind.Button, this.originX, this.originY, true, 0.0, 0.0);
						this.pointer(AreaPointerKind.Button, x, y, false, 0.0, 0.0);
					}
				}
				if (last) { this.phase = TouchPhase.Idle; }
			},
			TouchPhase.Pressing => {
				if (f.id === this.primary) {
					this.pointer(AreaPointerKind.Button, x, y, false, 0.0, 0.0);
					this.phase = last ? TouchPhase.Idle : TouchPhase.Spent;
				}
			},
			TouchPhase.Panning => {
				if (last) {
					this.phase = TouchPhase.Idle;
					const v = flingVelocity(f.tracker.estimate(frameNow() as float64));
					if (v !== null) { this.startMomentum(v as Offset); }
				}
			},
			TouchPhase.Spent => {
				if (last) { this.phase = TouchPhase.Idle; }
			},
			TouchPhase.Idle => { throw new Error(`sokol touch: touch ${t.id} ended while no touch was down`); },
		}
	}

	dropTap(): void {
		this.tapAlive = false;
		if (this.deadline >= 0) { cancelFrame(this.deadline); }
		this.deadline = -1;
	}

	watchDeadline(): void {
		const due = this.downAt + LONG_PRESS_MS;
		const wait = (time: number): void => {
			this.deadline = -1;
			if (this.phase !== TouchPhase.Pending || !this.tapAlive) { return; }
			if ((frameNow() as float64) < due) {
				this.deadline = requestFrame(wait);
				return;
			}
			this.tapAlive = false;
			this.phase = TouchPhase.Pressing;
			this.pointer(AreaPointerKind.Button, this.originX, this.originY, true, 0.0, 0.0);
		};
		this.deadline = requestFrame(wait);
	}

	startMomentum(velocity: Offset): void {
		this.fling = velocity;
		this.flingStart = -1.0;
		this.flung = { x: 0.0, y: 0.0 };
		this.flingDoneX = false;
		this.flingDoneY = false;
		const tolerance = 1.0 / (0.050 * (this.area.scale as float64));
		const tick = (time: number): void => {
			this.momentum = -1;
			const now = frameNow() as float64;
			if (this.flingStart < 0.0) {
				this.flingStart = now;
				this.momentum = requestFrame(tick);
				return;
			}
			const seconds = (now - this.flingStart) / 1000.0;
			const at: Offset = {
				x: this.flingDoneX ? this.flung.x : frictionAt(this.fling.x, seconds),
				y: this.flingDoneY ? this.flung.y : frictionAt(this.fling.y, seconds),
			};
			const stepX = at.x - this.flung.x;
			const stepY = at.y - this.flung.y;
			this.flung = at;
			const decay = Math.pow(FRICTION_DRAG, seconds);
			this.flingDoneX = this.flingDoneX || Math.abs(this.fling.x * decay) < tolerance;
			this.flingDoneY = this.flingDoneY || Math.abs(this.fling.y * decay) < tolerance;
			if (stepX !== 0.0 || stepY !== 0.0) { this.wheel(stepX, stepY); }
			if (!this.flingDoneX || !this.flingDoneY) { this.momentum = requestFrame(tick); }
		};
		this.momentum = requestFrame(tick);
	}

	stop(): void {
		this.dropTap();
		this.stopMomentum();
		this.fingers = [];
		this.phase = TouchPhase.Idle;
	}

	stopMomentum(): boolean {
		if (this.momentum < 0) { return false; }
		cancelFrame(this.momentum);
		this.momentum = -1;
		return true;
	}

	pointer(kind: AreaPointerKind, pixelX: float64, pixelY: float64, pressed: boolean, dx: float64, dy: float64): void {
		deliverPointer(this.area, {
			kind,
			pixelX,
			pixelY,
			button: kind === AreaPointerKind.Button ? 1 as int32 : 0 as int32,
			pressed,
			dx,
			dy,
			mods: this.mods,
		});
	}

	wheel(x: float64, y: float64): void {
		const scale = this.area.scale as float64;
		deliverPointer(this.area, {
			kind: AreaPointerKind.Wheel,
			pixelX: this.originX,
			pixelY: this.originY,
			button: 0 as int32,
			pressed: false,
			dx: 0.0 - x * scale,
			dy: y * scale,
			deltaMode: DOM_DELTA_PIXEL,
			mods: this.mods,
		});
	}
}
