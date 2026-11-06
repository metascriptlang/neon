import { LayoutAnimationPlan, LayoutPhase } from "../../motion/layoutAnimation";
import { supportsLinearEasing } from "../../motion/waapi";
import { cssLinear, sampleEasing } from "pulse/src/progress";
import { HTMLElement } from "../../render/htmlElements";

extern class document {
	static body: HTMLElement;
}

extern function requestAnimationFrame(callback: (time: number) => void): number;

interface Measured {
	el: HTMLElement;
	width: number;
	height: number;
}

let reflowSink = 0.0;

function cssCurve(phase: LayoutPhase): string {
	if (phase.css !== null) { return phase.css as string; }
	return supportsLinearEasing() ? cssLinear(sampleEasing(phase.curve, phase.duration)) : "ease-out";
}

function elements(): HTMLElement[] {
	const list = document.body.querySelectorAll("*");
	const out: HTMLElement[] = [];
	for (let i = 0; i < list.length; i += 1) { out.push(list.item(i) as HTMLElement); }
	return out;
}

function snapshot(): Map<HTMLElement, Measured> {
	const out = new Map<HTMLElement, Measured>();
	for (const el of elements()) { out.set(el, { el, width: el.offsetWidth, height: el.offsetHeight }); }
	return out;
}

class Written {
	read: () => string;
	write: (value: string) => void;
	kept: string;
	set: string = "";

	constructor(read: () => string, write: (value: string) => void) {
		this.read = read;
		this.write = write;
		this.kept = read();
	}

	put(value: string): void {
		this.write(value);
		this.set = this.read();
	}

	restore(): void {
		if (this.read() === this.set) { this.write(this.kept); }
	}
}

function restoreLater(written: Written[], phase: LayoutPhase): void {
	setTimeout((): void => {
		for (const entry of written) { entry.restore(); }
	}, phase.duration + phase.delay + 34);
}

function resize(el: HTMLElement, before: Measured, phase: LayoutPhase): void {
	const width = el.offsetWidth;
	const height = el.offsetHeight;
	if (width === before.width && height === before.height) { return; }
	const style = el.style;
	const transition = new Written((): string => style.transition, (v: string): void => { style.transition = v; });
	const w = new Written((): string => style.width, (v: string): void => { style.width = v; });
	const h = new Written((): string => style.height, (v: string): void => { style.height = v; });
	const overflow = new Written((): string => style.overflow, (v: string): void => { style.overflow = v; });
	transition.put("none");
	w.put(`${before.width}px`);
	h.put(`${before.height}px`);
	overflow.put("hidden");
	reflowSink += el.offsetHeight;
	const timing = `${phase.duration}ms ${cssCurve(phase)} ${phase.delay}ms`;
	transition.put(`width ${timing}, height ${timing}`);
	w.put(`${width}px`);
	h.put(`${height}px`);
	restoreLater([transition, w, h, overflow], phase);
}

function appear(el: HTMLElement, phase: LayoutPhase): void {
	const style = el.style;
	const transition = new Written((): string => style.transition, (v: string): void => { style.transition = v; });
	const timing = `${phase.duration}ms ${cssCurve(phase)} ${phase.delay}ms`;
	if (phase.property === "opacity") {
		const opacity = new Written((): string => style.opacity, (v: string): void => { style.opacity = v; });
		transition.put("none");
		opacity.put("0");
		reflowSink += el.offsetHeight;
		transition.put(`opacity ${timing}`);
		opacity.put(opacity.kept === "" ? "1" : opacity.kept);
		restoreLater([transition, opacity], phase);
		return;
	}
	const transform = new Written((): string => style.transform, (v: string): void => { style.transform = v; });
	const own = transform.kept === "" || transform.kept === "none" ? "" : `${transform.kept} `;
	const x = phase.property === "scaleY" ? 1 : 0;
	const y = phase.property === "scaleX" ? 1 : 0;
	transition.put("none");
	transform.put(`${own}scale(${x}, ${y})`);
	reflowSink += el.offsetHeight;
	transition.put(`transform ${timing}`);
	transform.put(transform.kept === "" ? "none" : transform.kept);
	restoreLater([transition, transform], phase);
}

// RN-web leaves LayoutAnimation a no-op; this measures every element before
// and after the change and transitions the sizes that moved (WORKAROUND.md N7).
export function animateDomLayout(plan: LayoutAnimationPlan): void {
	const before = snapshot();
	requestAnimationFrame((time: number): void => {
		const created: HTMLElement[] = [];
		for (const el of elements()) {
			if (before.has(el)) {
				if (plan.update !== null) { resize(el, before.get(el) as Measured, plan.update as LayoutPhase); }
				continue;
			}
			const parent = el.parentElement;
			if (plan.create !== null && parent !== null && before.has(parent as HTMLElement)) { created.push(el); }
		}
		for (const el of created) { appear(el, plan.create as LayoutPhase); }
	});
}
