import { Clock } from "./clock";
import { ComposedTrack, flatten, localTime, writerAt } from "./compose";
import { MotionDocument, MotionValue, findClip, validate } from "./document";
import { sampleTrack } from "./evaluate";
import { Composition, MotionTarget, TargetClaim } from "./target";

const PLAYHEAD_EPSILON: float64 = 1e-8;
const INFINITE_TOTAL_DURATION: float64 = 1e10;

export interface MotionBinding {
	slot: string;
	property: string;
	write: (value: MotionValue) => void;
	read: (() => MotionValue) | null;
	target?: MotionTarget;
}

export struct MotionOptions {
	delay: float64;
	repeat: int32;
	repeatDelay: float64;
	yoyo: boolean;
	timeScale: float64;
	paused: boolean;
	clock: Clock;
	composition: Composition;
}

export function motionOptions(clock: Clock): MotionOptions {
	return {
		delay: 0,
		repeat: 0,
		repeatDelay: 0,
		yoyo: false,
		timeScale: 1,
		paused: false,
		clock,
		composition: Composition.Replace,
	};
}

class ActiveTarget {
	binding: MotionBinding;
	writers: ComposedTrack[] = [];
	reached: boolean[] = [];
	claim: TargetClaim | null = null;
	lost: boolean = false;

	constructor(binding: MotionBinding) {
		this.binding = binding;
	}

	get label(): string {
		return this.binding.slot + "." + this.binding.property;
	}
}

function fail(message: string): never {
	throw new Error("motion: " + message);
}

function targetKey(slot: string, property: string): string {
	return slot + "\n" + property;
}

function roundPrecise(value: float64): float64 {
	return Math.round(value * 1e8) / 1e8;
}

function cycleIndex(totalTime: float64, cycle: float64): int32 {
	const ratio = roundPrecise(totalTime / cycle);
	const whole = Math.floor(ratio);
	return (ratio !== 0 && whole === ratio ? whole - 1 : whole) as int32;
}

function compile(doc: MotionDocument, bindings: MotionBinding[]): ActiveTarget[] {
	validate(doc);
	const keys: string[] = [];
	const identities: MotionTarget[] = [];
	const targets: ActiveTarget[] = [];
	for (const binding of bindings) {
		const key = targetKey(binding.slot, binding.property);
		if (keys.includes(key)) { fail("duplicate binding for " + binding.slot + "." + binding.property); }
		keys.push(key);
		const identity = binding.target;
		if (identity !== null) {
			if (identities.includes(identity)) {
				const name = binding.slot + "." + binding.property;
				fail("bindings " + name + " and another share one target");
			}
			identities.push(identity);
		}
		targets.push(new ActiveTarget(binding));
	}
	for (const writer of flatten(doc)) {
		const name = writer.slot + "." + writer.track.property;
		const index = keys.indexOf(targetKey(writer.slot, writer.track.property));
		if (index < 0) { fail("no binding for track " + name); }
		const writers = targets[index].writers;
		if (writers.length > 0 && writers[0].track.kind !== writer.track.kind) {
			fail("tracks of different kinds write " + name);
		}
		writers.push(writer);
		targets[index].reached.push(false);
	}
	for (const target of targets) {
		if (target.writers.length === 0) {
			fail("binding " + target.binding.slot + "." + target.binding.property + " has no track");
		}
	}
	return targets;
}

export class MotionPlayer {
	onStart: (() => void) | null = null;
	onUpdate: (() => void) | null = null;
	onRepeat: (() => void) | null = null;
	onComplete: (() => void) | null = null;
	onReverseComplete: (() => void) | null = null;

	private targets: ActiveTarget[];
	private clock: Clock;
	private iterationDuration: float64;
	private delayTime: float64;
	private repeatCount: int32;
	private repeatGap: float64;
	private yoyoing: boolean;
	private totalDur: float64;
	private scale: float64;
	private isPaused: boolean;
	private composition: Composition;
	private isCancelled: boolean = false;
	private isDisposed: boolean = false;
	private initted: boolean = false;
	private initial: MotionValue[] = [];
	private playhead: float64;
	private renderedTotalTime: float64 = 0;
	private renderedTime: float64 = 0;
	private renderSerial: int32 = 0;
	private frameId: int32 = 0;
	private lastFrameTime: float64 = 0;

	constructor(doc: MotionDocument, bindings: MotionBinding[], options: MotionOptions) {
		this.targets = compile(doc, bindings);
		if (!Number.isFinite(options.delay) || options.delay < 0) { fail("delay must be finite and not negative"); }
		if (options.repeat < -1) { fail("repeat must be -1 or more"); }
		if (!Number.isFinite(options.repeatDelay) || options.repeatDelay < 0) {
			fail("repeatDelay must be finite and not negative");
		}
		this.clock = options.clock;
		this.iterationDuration = findClip(doc, doc.root).duration;
		this.delayTime = options.delay;
		this.repeatCount = options.repeat;
		this.repeatGap = options.repeat === 0 ? 0 : options.repeatDelay;
		this.yoyoing = options.yoyo;
		this.totalDur = this.computeTotalDuration();
		this.scale = this.checkedScale(options.timeScale);
		this.isPaused = options.paused;
		this.composition = options.composition;
		this.playhead = -options.delay;
		this.sync();
	}

	get disposed(): boolean {
		return this.isDisposed;
	}

	get paused(): boolean {
		this.live();
		return this.isPaused;
	}

	get cancelled(): boolean {
		this.live();
		return this.isCancelled;
	}

	get reversed(): boolean {
		this.live();
		return this.scale < 0;
	}

	get timeScale(): float64 {
		this.live();
		return this.scale;
	}

	get time(): float64 {
		this.live();
		return this.renderedTime;
	}

	get totalTime(): float64 {
		this.live();
		return this.renderedTotalTime;
	}

	get rawTime(): float64 {
		this.live();
		return this.playhead;
	}

	get duration(): float64 {
		this.live();
		return this.iterationDuration;
	}

	get totalDuration(): float64 {
		this.live();
		return this.totalDur;
	}

	get iteration(): int32 {
		this.live();
		return this.repeatCount === 0 ? 1 : cycleIndex(this.renderedTotalTime, this.cycle()) + 1;
	}

	get progress(): float64 {
		this.live();
		return Math.min(1, this.renderedTime / this.iterationDuration);
	}

	get totalProgress(): float64 {
		this.live();
		return Math.min(1, this.renderedTotalTime / this.totalDur);
	}

	get isActive(): boolean {
		this.live();
		return this.frameId !== 0 && this.initted && this.playhead >= 0;
	}

	play(from: float64 | null = null, suppressEvents: boolean = true): void {
		this.live();
		if (from !== null) { this.moveTo(from, suppressEvents); }
		this.scale = Math.abs(this.scale);
		this.release();
	}

	reverse(from: float64 | null = null, suppressEvents: boolean = true): void {
		this.live();
		if (from !== null) { this.moveTo(from !== 0 ? from : this.totalDur, suppressEvents); }
		this.scale = -Math.abs(this.scale);
		this.release();
	}

	pause(atTime: float64 | null = null, suppressEvents: boolean = true): void {
		this.live();
		if (atTime !== null) { this.moveTo(atTime, suppressEvents); }
		this.isPaused = true;
		this.sync();
	}

	resume(): void {
		this.live();
		this.release();
	}

	restart(includeDelay: boolean = false, suppressEvents: boolean = true): void {
		this.live();
		this.scale = Math.abs(this.scale);
		this.release();
		this.moveTo(includeDelay ? -this.delayTime : 0, suppressEvents);
	}

	seek(position: float64, suppressEvents: boolean = true): void {
		this.live();
		this.moveTo(position, suppressEvents);
	}

	setTotalTime(value: float64, suppressEvents: boolean = false): void {
		this.live();
		this.moveTo(value, suppressEvents);
	}

	setTime(value: float64, suppressEvents: boolean = false): void {
		this.live();
		const reflected = this.yoyoing && this.iteration % 2 === 0;
		const inIteration = reflected ? this.iterationDuration - value : value;
		this.moveTo(inIteration + this.elapsedCycleDuration(), suppressEvents);
	}

	setTotalProgress(value: float64, suppressEvents: boolean = false): void {
		this.live();
		this.moveTo(this.totalDur * value, suppressEvents);
	}

	setProgress(value: float64, suppressEvents: boolean = false): void {
		this.setTime(this.iterationDuration * value, suppressEvents);
	}

	setTimeScale(value: float64): void {
		this.live();
		this.scale = this.checkedScale(value);
		this.sync();
	}

	finish(): void {
		this.live();
		this.moveTo(this.scale < 0 ? 0 : this.totalDur, false);
	}

	cancel(): void {
		this.live();
		this.isPaused = true;
		this.isCancelled = true;
		this.releaseTargets();
		this.sync();
	}

	revert(): void {
		this.live();
		for (const target of this.targets) {
			if (target.binding.read === null) {
				fail("cannot revert: binding " + target.binding.slot + "." + target.binding.property + " has no read");
			}
		}
		this.isPaused = true;
		this.isCancelled = true;
		this.releaseTargets();
		this.sync();
		if (this.initted) {
			for (let i: int32 = 0; i < this.targets.length; i += 1) {
				this.targets[i].binding.write(this.initial[i]);
				if (this.isDisposed) { return; }
			}
		}
		this.renderSerial += 1;
		for (const target of this.targets) { target.reached.fill(false); }
		this.initted = false;
		this.initial = [];
		this.playhead = -this.delayTime;
		this.renderedTotalTime = 0;
		this.renderedTime = 0;
	}

	dispose(): void {
		this.live();
		this.isDisposed = true;
		this.releaseTargets();
		this.sync();
		this.onStart = null;
		this.onUpdate = null;
		this.onRepeat = null;
		this.onComplete = null;
		this.onReverseComplete = null;
	}

	private live(): void {
		if (this.isDisposed) { fail("player is disposed"); }
	}

	private checkedScale(value: float64): float64 {
		if (!Number.isFinite(value) || value === 0) { fail("timeScale must be finite and not zero"); }
		return value;
	}

	private computeTotalDuration(): float64 {
		if (this.repeatCount < 0) { return INFINITE_TOTAL_DURATION; }
		const repeats = this.repeatCount as float64;
		return roundPrecise(this.iterationDuration * (repeats + 1) + this.repeatGap * repeats);
	}

	private cycle(): float64 {
		return this.iterationDuration + this.repeatGap;
	}

	private elapsedCycleDuration(): float64 {
		if (this.repeatCount === 0) { return 0; }
		return cycleIndex(this.renderedTotalTime, this.cycle()) * this.cycle();
	}

	private wantsFrame(): boolean {
		if (this.isDisposed || this.isPaused) { return false; }
		return this.scale > 0 ? this.playhead < this.totalDur : this.playhead > 0;
	}

	private requestFrame(): void {
		this.frameId = this.clock.request((time: float64): void => this.tick(time));
	}

	private sync(): void {
		if (!this.wantsFrame()) {
			if (this.frameId !== 0) {
				this.clock.cancel(this.frameId);
				this.frameId = 0;
			}
			return;
		}
		if (this.frameId === 0) {
			this.lastFrameTime = this.clock.now();
			this.requestFrame();
		}
	}

	private release(): void {
		this.isPaused = false;
		this.isCancelled = false;
		this.sync();
	}

	private tick(time: float64): void {
		this.frameId = 0;
		const lowest = this.scale < 0 ? 0 : -this.delayTime;
		const delta = Math.max(0, time - this.lastFrameTime);
		this.lastFrameTime = time;
		const next = Math.min(Math.max(this.playhead + delta * this.scale, lowest), this.totalDur);
		this.moveTo(next, false);
		if (this.wantsFrame() && this.frameId === 0) { this.requestFrame(); }
	}

	private moveTo(position: float64, suppressEvents: boolean): void {
		this.playhead = Math.min(Math.max(position, -this.delayTime), this.totalDur);
		this.render(position, suppressEvents);
		this.sync();
	}

	private superseded(serial: int32): boolean {
		return this.isDisposed || serial !== this.renderSerial;
	}

	private render(position: float64, suppressEvents: boolean): void {
		const total = this.totalDur;
		const negative = position < 0;
		const totalTime = position > total - PLAYHEAD_EPSILON && !negative
			? total
			: position < PLAYHEAD_EPSILON ? 0 : position;
		if (totalTime === this.renderedTotalTime && position !== 0) { return; }
		const repeating = this.repeatCount !== 0;
		const cycle = this.cycle();
		const previousIteration = repeating ? cycleIndex(this.renderedTotalTime, cycle) : 0;
		let time = totalTime;
		let iteration: int32 = 0;
		let reflected = false;
		if (repeating) {
			time = roundPrecise(totalTime % cycle);
			if (totalTime === total && this.repeatCount > 0) {
				iteration = this.repeatCount;
				time = this.iterationDuration;
			} else {
				const whole = roundPrecise(totalTime / cycle);
				iteration = Math.floor(whole) as int32;
				if (iteration > 0 && iteration === whole) {
					time = this.iterationDuration;
					iteration -= 1;
				} else if (time > this.iterationDuration) {
					time = this.iterationDuration;
				}
			}
			reflected = this.yoyoing && iteration % 2 === 1;
			if (reflected) { time = this.iterationDuration - time; }
			if (time === this.renderedTime && this.initted && iteration === previousIteration) {
				this.renderedTotalTime = totalTime;
				return;
			}
		}
		const previousTime = this.renderedTime;
		if (!this.initted) { this.capture(); }
		this.renderedTotalTime = totalTime;
		this.renderedTime = time;
		this.renderSerial += 1;
		const serial = this.renderSerial;
		if (previousTime === 0 && totalTime !== 0 && !suppressEvents && previousIteration === 0) {
			const listener = this.onStart;
			if (listener !== null) { listener(); }
			if (this.superseded(serial)) { return; }
		}
		for (const target of this.targets) {
			for (let i: int32 = 0; i < target.writers.length; i += 1) {
				if (target.writers[i].start <= time) { target.reached[i] = true; }
			}
			const index = writerAt(target.writers, target.reached, time);
			if (index < 0 || target.lost) { continue; }
			const writer = target.writers[index];
			const value = this.held(target, sampleTrack(writer.track, writer.localTime(time)));
			if (this.superseded(serial)) { return; }
			target.binding.write(value);
			if (this.superseded(serial)) { return; }
		}
		if (this.scale > 0 ? totalTime === total : totalTime === 0) { this.releaseTargets(); }
		if (!suppressEvents) {
			const listener = this.onUpdate;
			if (listener !== null) { listener(); }
			if (this.superseded(serial)) { return; }
			if (repeating && iteration !== previousIteration) {
				const repeated = this.onRepeat;
				if (repeated !== null) { repeated(); }
				if (this.superseded(serial)) { return; }
			}
		}
		const atEnd = totalTime === total;
		if (!suppressEvents && (atEnd || totalTime === 0)) {
			if (!(negative && previousTime === 0) && (totalTime !== 0 || previousTime !== 0 || reflected)) {
				const finished = atEnd ? this.onComplete : this.onReverseComplete;
				if (finished !== null) { finished(); }
			}
		}
	}

	private held(target: ActiveTarget, value: MotionValue): MotionValue {
		const identity = target.binding.target;
		if (identity === null || this.composition === Composition.None) { return value; }
		const blend = this.composition === Composition.Blend;
		let claim = target.claim;
		if (claim === null) {
			const end = blend ? this.endValue(target) : value;
			claim = identity.claim(
				this.composition,
				value,
				end,
				target.label,
				null,
				(): void => this.replaced(target),
			);
			target.claim = claim;
		}
		return blend ? identity.blended(claim, value, target.label) : value;
	}

	private endValue(target: ActiveTarget): MotionValue {
		const reflected = this.yoyoing && this.repeatCount > 0 && this.repeatCount % 2 === 1;
		const time = reflected ? 0 : this.iterationDuration;
		const reached = target.writers.map((): boolean => true);
		const writer = target.writers[writerAt(target.writers, reached, time)];
		return sampleTrack(writer.track, writer.localTime(time));
	}

	private replaced(target: ActiveTarget): void {
		target.claim = null;
		target.lost = true;
		if (this.targets.every((other: ActiveTarget): boolean => other.lost)) { this.cancel(); }
	}

	private releaseTargets(): void {
		for (const target of this.targets) {
			const claim = target.claim;
			const identity = target.binding.target;
			if (claim !== null && identity !== null) { identity.release(claim); }
			target.claim = null;
			target.lost = false;
		}
	}

	private capture(): void {
		this.initted = true;
		this.initial = [];
		for (const target of this.targets) {
			const read = target.binding.read;
			if (read !== null) { this.initial.push(read()); }
		}
	}
}
