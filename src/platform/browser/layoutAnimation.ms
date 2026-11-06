import { LayoutAnimationPlan, LayoutPhase } from "../../motion/layoutAnimation";
import { hostMotionPolicy } from "../../motion/neon";
import { supportsLinearEasing } from "../../motion/waapi";
import { cssLinear, sampleEasing } from "pulse/src/progress";
import { HTMLElement } from "../../render/htmlElements";

extern class document {
	static body: HTMLElement;
}

extern function requestAnimationFrame(callback: (time: number) => void): number;

interface Measured {
	width: number;
	height: number;
}

interface Resize {
	el: HTMLElement;
	from: Measured;
	to: Measured;
}

let reflowSink = 0.0;

function cssCurve(phase: LayoutPhase): string {
	if (phase.css !== null) { return phase.css as string; }
	return supportsLinearEasing() ? cssLinear(sampleEasing(phase.curve, phase.duration)) : "ease-out";
}

function timing(phase: LayoutPhase): string {
	return `${phase.duration}ms ${cssCurve(phase)} ${phase.delay}ms`;
}

function elements(): HTMLElement[] {
	const list = document.body.querySelectorAll("*");
	const out: HTMLElement[] = [];
	for (let i = 0; i < list.length; i += 1) { out.push(list.item(i) as HTMLElement); }
	return out;
}

function snapshot(): Map<HTMLElement, Measured> {
	const out = new Map<HTMLElement, Measured>();
	for (const el of elements()) { out.set(el, { width: el.offsetWidth, height: el.offsetHeight }); }
	return out;
}

class Written {
	read: () => string;
	write: (value: string) => void;
	kept: string = "";
	set: string = "";
	held: boolean = false;

	constructor(read: () => string, write: (value: string) => void) {
		this.read = read;
		this.write = write;
	}

	base(): string {
		return this.held && this.read() === this.set ? this.kept : this.read();
	}

	put(value: string): void {
		this.kept = this.base();
		this.write(value);
		this.set = this.read();
		this.held = true;
	}

	restore(): void {
		if (this.held && this.read() === this.set) { this.write(this.kept); }
		this.held = false;
	}
}

class Animated {
	el: HTMLElement;
	transition: Written;
	width: Written;
	height: Written;
	overflow: Written;
	opacity: Written;
	transform: Written;
	runs: int32 = 0;

	constructor(el: HTMLElement) {
		this.el = el;
		const style = el.style;
		this.transition = new Written((): string => style.transition, (v: string): void => { style.transition = v; });
		this.width = new Written((): string => style.width, (v: string): void => { style.width = v; });
		this.height = new Written((): string => style.height, (v: string): void => { style.height = v; });
		this.overflow = new Written((): string => style.overflow, (v: string): void => { style.overflow = v; });
		this.opacity = new Written((): string => style.opacity, (v: string): void => { style.opacity = v; });
		this.transform = new Written((): string => style.transform, (v: string): void => { style.transform = v; });
	}

	restore(): void {
		this.transition.restore();
		this.width.restore();
		this.height.restore();
		this.overflow.restore();
		this.opacity.restore();
		this.transform.restore();
	}
}

const animated = new Map<HTMLElement, Animated>();

function animatedOf(el: HTMLElement): Animated {
	if (!animated.has(el)) { animated.set(el, new Animated(el)); }
	return animated.get(el) as Animated;
}

function restoreLater(record: Animated, phase: LayoutPhase): void {
	record.runs += 1;
	const run = record.runs;
	setTimeout((): void => {
		if (record.runs !== run) { return; }
		record.restore();
		animated.delete(record.el);
	}, phase.duration + phase.delay + 34);
}

function resizing(el: HTMLElement): boolean {
	return animated.has(el) && (animated.get(el) as Animated).height.held;
}

function startResize(change: Resize): void {
	const record = animatedOf(change.el);
	record.transition.put("none");
	record.width.put(`${change.from.width}px`);
	record.height.put(`${change.from.height}px`);
	record.overflow.put("hidden");
}

function endResize(change: Resize, phase: LayoutPhase): void {
	const record = animatedOf(change.el);
	const t = timing(phase);
	record.transition.put(`width ${t}, height ${t}`);
	record.width.put(`${change.to.width}px`);
	record.height.put(`${change.to.height}px`);
	restoreLater(record, phase);
}

function startAppear(el: HTMLElement, phase: LayoutPhase): void {
	const record = animatedOf(el);
	record.transition.put("none");
	if (phase.property === "opacity") {
		record.opacity.put("0");
		return;
	}
	const own = record.transform.base();
	const prefix = own === "" || own === "none" ? "" : `${own} `;
	const x = phase.property === "scaleY" ? 1 : 0;
	const y = phase.property === "scaleX" ? 1 : 0;
	record.transform.put(`${prefix}scale(${x}, ${y})`);
}

function endAppear(el: HTMLElement, phase: LayoutPhase): void {
	const record = animatedOf(el);
	if (phase.property === "opacity") {
		record.transition.put(`opacity ${timing(phase)}`);
		record.opacity.put(record.opacity.kept === "" ? "1" : record.opacity.kept);
	} else {
		record.transition.put(`transform ${timing(phase)}`);
		record.transform.put(record.transform.kept === "" ? "none" : record.transform.kept);
	}
	restoreLater(record, phase);
}

// RN-web leaves LayoutAnimation a no-op; this measures every element before
// and after the change and transitions the sizes that moved (WORKAROUND.md N7).
export function animateDomLayout(plan: LayoutAnimationPlan): void {
	if (hostMotionPolicy().reducedMotion) { return; }
	const before = snapshot();
	requestAnimationFrame((time: number): void => {
		const created: HTMLElement[] = [];
		for (const el of elements()) {
			if (before.has(el)) {
				if (plan.update === null || resizing(el)) { continue; }
				const from = before.get(el) as Measured;
				const to: Measured = { width: el.offsetWidth, height: el.offsetHeight };
				if (to.width !== from.width || to.height !== from.height) {
					const change: Resize = { el, from, to };
					startResize(change);
					reflowSink += el.offsetHeight;
					endResize(change, plan.update as LayoutPhase);
				}
				continue;
			}
			const parent = el.parentElement;
			if (plan.create !== null && parent !== null && before.has(parent as HTMLElement)) { created.push(el); }
		}
		for (const el of created) {
			startAppear(el, plan.create as LayoutPhase);
			reflowSink += el.offsetHeight;
			endAppear(el, plan.create as LayoutPhase);
		}
	});
}
