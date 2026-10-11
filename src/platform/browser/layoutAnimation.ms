import { LayoutAnimationPlan, LayoutPhase, onConfigureNext } from "../../animation/layoutAnimation";

extern class CSSStyleDeclaration {
	width: string;
	height: string;
	opacity: string;
	overflow: string;
	transition: string;
}

extern class HTMLElement {
	offsetWidth: number;
	offsetHeight: number;
	parentNode: HTMLElement | null;
	style: CSSStyleDeclaration;
	extern querySelectorAll(selector: cstring): NodeList;
}

extern class NodeList {
	length: number;
	extern item(index: number): HTMLElement;
}

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

function elements(): HTMLElement[] {
	const list = document.body.querySelectorAll("*");
	const out: HTMLElement[] = [];
	for (let i = 0; i < list.length; i += 1) { out.push(list.item(i)); }
	return out;
}

function snapshot(): Map<HTMLElement, Measured> {
	const out = new Map<HTMLElement, Measured>();
	for (const el of elements()) { out.set(el, { el, width: el.offsetWidth, height: el.offsetHeight }); }
	return out;
}

function resize(el: HTMLElement, before: Measured, phase: LayoutPhase): void {
	const width = el.offsetWidth;
	const height = el.offsetHeight;
	if (width === before.width && height === before.height) { return; }
	const style = el.style;
	const keepWidth = style.width;
	const keepHeight = style.height;
	const keepOverflow = style.overflow;
	const keepTransition = style.transition;
	style.transition = "none";
	style.width = `${before.width}px`;
	style.height = `${before.height}px`;
	style.overflow = "hidden";
	reflowSink += el.offsetHeight;
	const timing = `${phase.duration}ms ${phase.cssCurve} ${phase.delay}ms`;
	style.transition = `width ${timing}, height ${timing}`;
	style.width = `${width}px`;
	style.height = `${height}px`;
	setTimeout((): void => {
		style.transition = keepTransition;
		style.width = keepWidth;
		style.height = keepHeight;
		style.overflow = keepOverflow;
	}, phase.duration + phase.delay + 34);
}

function fadeIn(el: HTMLElement, phase: LayoutPhase): void {
	const style = el.style;
	const keepOpacity = style.opacity;
	const keepTransition = style.transition;
	style.transition = "none";
	style.opacity = "0";
	reflowSink += el.offsetHeight;
	style.transition = `opacity ${phase.duration}ms ${phase.cssCurve} ${phase.delay}ms`;
	style.opacity = keepOpacity === "" ? "1" : keepOpacity;
	setTimeout((): void => {
		style.transition = keepTransition;
		style.opacity = keepOpacity;
	}, phase.duration + phase.delay + 34);
}

function animate(plan: LayoutAnimationPlan): void {
	const before = snapshot();
	requestAnimationFrame((time: number): void => {
		const created: HTMLElement[] = [];
		for (const el of elements()) {
			if (before.has(el)) {
				if (plan.update !== null) { resize(el, before.get(el) as Measured, plan.update as LayoutPhase); }
				continue;
			}
			const parent = el.parentNode;
			if (plan.create !== null && parent !== null && before.has(parent as HTMLElement)) { created.push(el); }
		}
		for (const el of created) { fadeIn(el, plan.create as LayoutPhase); }
	});
}

let installed = false;

// RN-web leaves LayoutAnimation a no-op; this measures every element before
// and after the change and transitions the sizes that moved (WORKAROUND.md N7).
export function installDomLayoutAnimation(): void {
	if (installed) { return; }
	installed = true;
	onConfigureNext(animate);
}
