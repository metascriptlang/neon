import {
	ScrollAxis,
	ScrollSource,
	TimeSource,
	ViewRange,
	scrollSource,
	viewSource,
} from "pulse/src/scroll";
import { createRoot } from "../../src/core/owner";
import { MotionSignals, useAnimatedValue } from "../../src/motion/neon";
import { createSignal } from "../../src/core/signal";
import { Show } from "../../src/macros/ui/flow";
import { AnimatedValue } from "pulse/src/value";
import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ViewHandle } from "../../src/components/primitives";
import { sleepAsync } from "std/core/promise";
import {
	MotionDocument,
	MotionTrack,
	MotionValue,
	linearKeyframe,
	numberValue,
} from "pulse/src/document";
import {
	MotionBinding,
	MotionOptions,
	MotionPlayer,
	motionOptions,
} from "pulse/src/player";
import {
	ElementValue,
	MotionElement,
	browserMotionPlayer,
	elementScrollSource,
	elementValue,
	elementViewSubject,
	frameClock,
	motionElements,
} from "../../src/motion/waapi";
import { MotionPolicy } from "pulse/src/policy";
import { MotionShowcase } from "../../examples/motionShowcase/showcase";
import { decay, spring, timing } from "pulse/src/value";
import { decayConfig } from "pulse/src/decay";
import { Easing } from "pulse/src/easing";

extern class Animation {}

extern class CSSStyleDeclaration {
	opacity: string;
	translate: string;
	display: string;
}

extern class HTMLElement {
	style: CSSStyleDeclaration;
	extern getAnimations(): Animation[];
	extern remove(): void;
}

extern function computed(
	el: HTMLElement,
	property: string,
): string from "getComputedStyle(#)[#]";

class StyleWrites {
	count: int32 = 0;
}

extern function watchStyle(el: HTMLElement, writes: StyleWrites): () => void from
	"((el, w) => { const o = new MutationObserver((list) => { w.count += list.length; }); o.observe(el, { attributes: true, attributeFilter: ['style'] }); return () => { w.count += o.takeRecords().length; o.disconnect(); }; })(#, #)";

class FrameCount {
	count: int32 = 0;
}

extern function countFrames(frames: FrameCount): () => void from
	"(f => { const raf = globalThis.requestAnimationFrame; globalThis.requestAnimationFrame = (cb) => { f.count += 1; return raf(cb); }; return () => { globalThis.requestAnimationFrame = raf; }; })(#)";

extern function byText(text: string): HTMLElement from
	"(t => [...document.body.querySelectorAll('*')].find((e) => e.children.length === 0 && e.textContent === t).parentElement)(#)";

extern function clickOn(el: HTMLElement): void from "(el => el.click())(#)";

extern function bodyText(): string from "(() => document.body.textContent)()";

extern function makeScroller(): HTMLElement from
	"(() => { const s = document.createElement('div'); s.style.cssText = 'height: 50px; width: 50px; overflow-y: scroll; overflow-x: hidden'; const c = document.createElement('div'); c.style.height = '150px'; s.append(c); document.body.append(s); return s; })()";
extern function setScrollTop(el: HTMLElement, offset: float64): void from "((el, o) => { el.scrollTop = o; })(#, #)";
extern function timelinesOf(el: HTMLElement): string from
	"(el => el.getAnimations().map((a) => a.timeline.constructor.name).join())(#)";
extern function firstEasing(el: HTMLElement): string from
	"(el => { const a = el.getAnimations(); return a.length === 0 ? '' : a[0].effect.getKeyframes()[0].easing; })(#)";
extern function preferReducedMotion(): () => void from
	"(() => { const real = globalThis.matchMedia; globalThis.matchMedia = (q) => q === '(prefers-reduced-motion: reduce)' ? { matches: true, media: q } : real.call(globalThis, q); return () => { globalThis.matchMedia = real; }; })()";
extern function hideTypedOmFactories(): () => void from
	"(() => { const px = CSS.px; delete CSS.px; return () => { CSS.px = px; }; })()";
extern function hideTimelines(): () => void from
	"(() => { const saved = [globalThis.ScrollTimeline, globalThis.ViewTimeline]; delete globalThis.ScrollTimeline; delete globalThis.ViewTimeline; return () => { globalThis.ScrollTimeline = saved[0]; globalThis.ViewTimeline = saved[1]; }; })()";
extern function renderedFrames(): Promise<void> from
	"new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(() => done())))";
extern function makeScrollBox(style: string): HTMLElement from
	"(st => { const s = document.createElement('div'); s.style.cssText = 'width: 50px; height: 50px; overflow: scroll; ' + st; const c = document.createElement('div'); c.style.cssText = 'position: relative; width: 150px; height: 150px'; const subject = document.createElement('div'); subject.style.cssText = 'position: absolute; inset-inline-start: 70px; inset-block-start: 70px; width: 10px; height: 10px'; c.append(subject); s.append(c); document.body.append(s); return s; })(#)";
extern function boxSubject(scroller: HTMLElement): HTMLElement from "(s => s.firstChild.firstChild)(#)";
extern function scrollBoxTo(scroller: HTMLElement, left: float64, top: float64): void from
	"((s, l, t) => { s.scrollLeft = l; s.scrollTop = t; })(#, #, #)";
extern function rootScroller(): HTMLElement from "(() => document.scrollingElement)()";
extern function scrollPage(top: float64): void from "(t => { window.scrollTo(0, t); })(#)";
extern function makePageSubject(): HTMLElement from
	"(() => { const subject = document.createElement('div'); subject.style.cssText = 'position: absolute; top: 900px; left: 0; width: 10px; height: 10px'; const spacer = document.createElement('div'); spacer.style.height = '3000px'; subject.append(spacer); document.body.append(subject); return subject; })()";

class ScrollReads {
	styles: int32 = 0;
	offsets: int32 = 0;
}

extern function countScrollReads(scroller: HTMLElement, reads: ScrollReads): () => void from
	"((el, r) => { const style = globalThis.getComputedStyle; globalThis.getComputedStyle = (...a) => { r.styles += 1; return style.apply(globalThis, a); }; const d = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollTop'); Object.defineProperty(el, 'scrollTop', { configurable: true, get() { r.offsets += 1; return d.get.call(this); }, set(v) { d.set.call(this, v); } }); return () => { globalThis.getComputedStyle = style; delete el.scrollTop; }; })(#, #)";

function browserPlayer(
	doc: MotionDocument,
	elements: MotionElement[],
	bindings: MotionBinding[],
	options: MotionOptions,
): MotionPlayer {
	return browserMotionPlayer(doc, motionElements(elements), bindings, options);
}

function boxValue(
	initial: float64,
	policy: MotionPolicy,
	node: HostNode,
	property: string,
): ElementValue {
	const elements = motionElements([{ slot: "box", node }]);
	return elementValue(initial, policy, elements, "box", property) as ElementValue;
}

function ramp(slot: string, property: string, to: float64): MotionTrack {
	return {
		slot,
		property,
		kind: numberValue(0).kind,
		keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", 1000, to)],
	};
}

function documentOf(tracks: MotionTrack[]): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [
			{
				id: "main",
				duration: 1000,
				tracks,
				placements: [],
				labels: [],
			},
		],
	};
}

function mount(): HostNode {
	const nodes: HostNode[] = [];
	render(
		element(
			<View
				ref={(h: ViewHandle): void => { nodes.push(h.node); }}
				style={{
					width: 40,
					height: 40,
					backgroundColor: "#333",
				}}
			/>,
		),
		domHost(),
		documentBody(),
	);
	return nodes[0];
}

function dom(node: HostNode): HTMLElement {
	return node as unknown as HTMLElement;
}

function opacity(el: HTMLElement): float64 {
	return parseFloat(computed(el, "opacity"));
}

function translated(el: HTMLElement): float64 {
	return parseFloat(computed(el, "translate"));
}

function near(a: float64, b: float64, tolerance: float64): boolean {
	return Math.abs(a - b) <= tolerance;
}

function paused(): MotionOptions {
	return {
		...motionOptions(frameClock()),
		paused: true,
	};
}

function fadeAndSlide(
	node: HostNode,
	options: MotionOptions,
): MotionPlayer {
	const doc = documentOf(
		[ramp("box", "opacity", 1), ramp("box", "translateX", 100)],
	);
	return browserPlayer(
		doc,
		[
			{
				slot: "box",
				node,
			},
		],
		[],
		options,
	);
}

class Recorder {
	value: float64 = -1;

	binding(): MotionBinding {
		return {
			slot: "box",
			property: "progress",
			write: (value: MotionValue): void => { this.value = value.number; },
			read: (): MotionValue => numberValue(this.value),
		};
	}
}

test "a View's opacity and translate run as WAAPI animations with no inline writes until they finish" {
	const node = mount();
	const el = dom(node);
	const player = fadeAndSlide(node, motionOptions(frameClock()));
	let completed = 0;
	player.onComplete = (): void => { completed += 1; };
	await sleepAsync(500);
	assert el.getAnimations().length === 2, "animations: " +
		el.getAnimations().length.toString();
	assert el.style.opacity === "" && el.style.translate === "", "inline: " +
		el.style.opacity +
		" " +
		el.style.translate;
	assert opacity(el) > 0.2 && opacity(el) < 0.8, "mid opacity " +
		opacity(el).toString();
	assert translated(el) > 20 && translated(el) < 80, "mid translate " +
		computed(el, "translate");
	await sleepAsync(700);
	assert completed === 1, "completed " + completed.toString();
	assert opacity(el) === 1 && translated(el) === 100, computed(el, "opacity") +
		" " +
		computed(el, "translate");
	assert el.getAnimations().length === 0, "a finished animation is cancelled: " +
		el.getAnimations().length.toString();
	assert el.style.opacity === "1" && el.style.translate === "100px", "the end values are inline: " +
		el.style.opacity + " " + el.style.translate;
	el.style.opacity = "0.3";
	assert opacity(el) === 0.3, "a later inline style shows: " + computed(el, "opacity");
	player.dispose();
	el.remove();
}

test "a seek reads the value at that time from the browser's animation" {
	const node = mount();
	const el = dom(node);
	const player = fadeAndSlide(node, paused());
	player.seek(250);
	assert near(opacity(el), 0.25, 1e-3) &&
		near(translated(el), 25, 0.1), computed(el, "opacity") + " " +
		computed(el, "translate");
	player.seek(800);
	assert near(opacity(el), 0.8, 1e-3), computed(el, "opacity");
	await sleepAsync(100);
	assert near(opacity(el), 0.8, 1e-3), "a paused seek holds: " +
		computed(el, "opacity");
	player.dispose();
	el.remove();
}

test "pause holds and reverse runs the browser's animation backwards" {
	const node = mount();
	const el = dom(node);
	const player = fadeAndSlide(node, paused());
	player.seek(500);
	player.play();
	await sleepAsync(150);
	player.pause();
	const held = opacity(el);
	assert held > 0.55, "played forward: " + held.toString();
	await sleepAsync(150);
	assert opacity(el) === held, "paused at " + held.toString() + ", now " +
		computed(el, "opacity");
	assert near(
		held,
		player.time / 1000,
		1e-3,
	), "browser at the player's playhead: " + held.toString() + " vs " +
		player.time.toString();
	player.reverse();
	await sleepAsync(150);
	assert opacity(el) < held - 0.05, "reversed below " + held.toString() +
		": " +
		computed(el, "opacity");
	player.dispose();
	el.remove();
}

test "cancel keeps the current value inline and revert restores the inline value before playback" {
	const node = mount();
	const el = dom(node);
	const player = fadeAndSlide(node, paused());
	player.seek(400);
	player.cancel();
	assert el.getAnimations().length === 0, "cancel removes the animations";
	assert near(parseFloat(el.style.opacity), 0.4, 1e-3), "committed inline: " +
		el.style.opacity;
	assert near(opacity(el), 0.4, 1e-3), computed(el, "opacity");
	await sleepAsync(100);
	assert near(opacity(el), 0.4, 1e-3), "holds after cancel: " +
		computed(el, "opacity");
	player.seek(600);
	assert el.getAnimations().length === 2 &&
		near(opacity(el), 0.6, 1e-3), "a seek after cancel plays again";
	player.revert();
	assert el.getAnimations().length === 0, "revert removes the animations";
	assert el.style.opacity === "" &&
		el.style.translate === "", "inline restored: " + el.style.opacity + " " +
		el.style.translate;
	assert opacity(el) === 1 && computed(el, "translate") === "none", computed(
		el,
		"opacity",
	) +
		" " +
		computed(el, "translate");
	player.dispose();
	el.remove();
}

test "a track WAAPI cannot run stays in step with the browser's track after pause and seek" {
	const node = mount();
	const el = dom(node);
	const recorder = new Recorder();
	const doc = documentOf(
		[ramp("box", "opacity", 1), ramp("box", "progress", 1)],
	);
	const player = browserPlayer(
		doc,
		[
			{
				slot: "box",
				node,
			},
		],
		[recorder.binding()],
		motionOptions(frameClock()),
	);
	await sleepAsync(200);
	assert el.getAnimations().length === 1, "only opacity goes to WAAPI";
	player.pause();
	assert recorder.value > 0.05, "the evaluator ran: " +
		recorder.value.toString();
	assert near(opacity(el), recorder.value, 1e-3), "paused together: " +
		computed(el, "opacity") +
		" vs " +
		recorder.value.toString();
	player.seek(300);
	assert near(recorder.value, 0.3, 1e-9) &&
		near(opacity(el), 0.3, 1e-3), computed(el, "opacity") + " vs " +
		recorder.value.toString();
	player.play();
	await sleepAsync(150);
	player.pause();
	assert near(opacity(el), recorder.value, 1e-3), "after resume: " +
		computed(el, "opacity") +
		" vs " +
		recorder.value.toString();
	player.dispose();
	el.remove();
}

test "dispose leaves no running animation and refuses later control" {
	const node = mount();
	const el = dom(node);
	const player = fadeAndSlide(node, motionOptions(frameClock()));
	await sleepAsync(100);
	assert el.getAnimations().length === 2;
	player.dispose();
	assert el.getAnimations().length === 0 && player.disposed;
	let message = "";
	try { player.play(); } catch (e) { message = e.message; }
	assert message === "motion: player is disposed", message;
	el.remove();
}

test "a track with neither a CSS property nor a binding is refused at construction" {
	const node = mount();
	const doc = documentOf([ramp("box", "progress", 1)]);
	let message = "";
	try {
		browserPlayer(
			doc,
			[
				{
					slot: "box",
					node,
				},
			],
			[],
			paused(),
		);
	} catch (e) { message = e.message; }
	assert message ===
		"motion: no browser binding for track box.progress", message;
	const orphan = documentOf([ramp("card", "opacity", 1)]);
	message = "";
	try {
		browserPlayer(
			orphan,
			[
				{
					slot: "box",
					node,
				},
			],
			[],
			paused(),
		);
	} catch (e) { message = e.message; }
	assert message ===
		"motion: no element for slot card of track card.opacity", message;
	dom(node).remove();
}

test "a player on an element's scroll source hands its WAAPI tracks to a ScrollTimeline the scroll drives" {
	const node = mount();
	const el = dom(node);
	const scroller = makeScroller();
	const source = scrollSource(elementScrollSource(scroller as unknown as HostNode));
	const player = fadeAndSlide(node, { ...motionOptions(frameClock()), source });
	await sleepAsync(60);
	assert timelinesOf(el) === "ScrollTimeline,ScrollTimeline", timelinesOf(el);
	setScrollTop(scroller, 50);
	await sleepAsync(60);
	assert near(translated(el), 50, 0.01) && near(opacity(el), 0.5, 1e-3),
		computed(el, "translate") + " " + computed(el, "opacity");
	assert el.style.translate === "", "the scroll moved no inline value: " + el.style.translate;
	player.dispose();
	assert el.getAnimations().length === 0 && el.style.translate === "50px", el.style.translate;
	scroller.remove();
	el.remove();
}

test "a scroll source no element backs runs the whole player on the evaluator" {
	const node = mount();
	const el = dom(node);
	let offset: float64 = 0;
	const scroller: ScrollSource = {
		offset: (axis: ScrollAxis): float64 => offset,
		max: (axis: ScrollAxis): float64 => 100,
		viewport: (axis: ScrollAxis): float64 => 50,
	};
	const player = fadeAndSlide(node, { ...motionOptions(frameClock()), source: scrollSource(scroller) });
	offset = 25;
	await sleepAsync(60);
	assert el.getAnimations().length === 0 && el.style.translate === "25px", el.style.translate;
	player.dispose();
	el.remove();
}

async function slideOn(source: () => TimeSource, timelines: boolean): Promise<float64> {
	const node = mount();
	const el = dom(node);
	const restore = timelines ? null : hideTimelines();
	const player = browserPlayer(
		documentOf([ramp("box", "translateX", 100)]),
		[{ slot: "box", node }],
		[],
		{ ...motionOptions(frameClock()), source: source() },
	);
	if (restore !== null) { restore(); }
	await renderedFrames();
	await renderedFrames();
	const shown = translated(el);
	player.dispose();
	el.remove();
	return shown;
}

async function sameWithoutTimelines(what: string, source: () => TimeSource): Promise<string> {
	const native = await slideOn(source, true);
	const evaluated = await slideOn(source, false);
	return near(native, evaluated, 0.5) ? "" : what + ": Chrome " + native.toString() +
		", evaluator " + evaluated.toString() + "; ";
}

test "without scroll timelines an rtl or vertical-rl scroller drives the evaluator from its start edge, as Chrome's timelines do" {
	let failures = "";
	for (const style of ["direction: rtl", "writing-mode: vertical-rl"]) {
		const scroller = makeScrollBox(style);
		scrollBoxTo(scroller, -25, 30);
		const node = scroller as unknown as HostNode;
		for (const axis of [ScrollAxis.Block, ScrollAxis.Inline]) {
			const name = style + (axis === ScrollAxis.Block ? " block" : " inline");
			failures += await sameWithoutTimelines(
				name + " scroll",
				(): TimeSource => scrollSource(elementScrollSource(node), axis),
			);
			failures += await sameWithoutTimelines(
				name + " view",
				(): TimeSource => viewSource(
					elementScrollSource(node),
					elementViewSubject(boxSubject(scroller) as unknown as HostNode, node),
					ViewRange.Cover,
					{ start: 0, end: 0 },
					axis,
				),
			);
		}
		scroller.remove();
	}
	assert failures === "", failures;
}

test "without scroll timelines a view of the page scroller places its subject as Chrome's ViewTimeline does" {
	const subject = makePageSubject();
	scrollPage(500);
	const page = rootScroller() as unknown as HostNode;
	const failures = await sameWithoutTimelines(
		"page view",
		(): TimeSource => viewSource(
			elementScrollSource(page),
			elementViewSubject(subject as unknown as HostNode, page),
		),
	);
	scrollPage(0);
	subject.remove();
	assert failures === "", failures;
}

test "without scroll timelines a scroll player reads the computed style once and the offset once per frame" {
	const node = mount();
	const el = dom(node);
	const scroller = makeScroller();
	setScrollTop(scroller, 30);
	const restore = hideTimelines();
	const source = scrollSource(elementScrollSource(scroller as unknown as HostNode));
	const player = fadeAndSlide(node, { ...motionOptions(frameClock()), source });
	restore();
	await renderedFrames();
	const frames = new FrameCount();
	const stopFrames = countFrames(frames);
	const reads = new ScrollReads();
	const stopReads = countScrollReads(scroller, reads);
	await sleepAsync(100);
	stopReads();
	stopFrames();
	const shown = translated(el);
	player.dispose();
	scroller.remove();
	el.remove();
	assert near(shown, 30, 0.01), shown.toString();
	assert frames.count > 3 && reads.styles === 0 && reads.offsets <= frames.count,
		"frames " + frames.count.toString() + ", computed styles " + reads.styles.toString() +
			", offsets " + reads.offsets.toString();
}

test "a view player hands its inset to ViewTimeline where CSS Typed OM has no px factory" {
	const node = mount();
	const el = dom(node);
	const scroller = makeScrollBox("");
	const scrolled = scroller as unknown as HostNode;
	const restore = hideTypedOmFactories();
	let message = "";
	let timelines = "";
	try {
		const player = fadeAndSlide(node, {
			...motionOptions(frameClock()),
			source: viewSource(
				elementScrollSource(scrolled),
				elementViewSubject(boxSubject(scroller) as unknown as HostNode, scrolled),
				ViewRange.Cover,
				{ start: 10, end: 5 },
			),
		});
		await renderedFrames();
		timelines = timelinesOf(el);
		player.dispose();
	} catch (e) { message = e.message; }
	restore();
	assert message === "" && timelines === "ViewTimeline,ViewTimeline", message + timelines;
	scroller.remove();
	el.remove();
}

test "a browser user's reduced motion preference is the default policy, and an explicit policy still wins" {
	const restore = preferReducedMotion();
	const made: AnimatedValue[] = [];
	const dispose = createRoot((dispose: () => void): () => void => {
		made.push(useAnimatedValue(0)[1]);
		made.push(useAnimatedValue(0, new MotionPolicy())[1]);
		return dispose;
	});
	restore();
	made[0].animate(timing(1, { duration: 1000 }));
	made[1].animate(timing(1, { duration: 1000 }));
	const preferred = made[0].get();
	const reduced = !made[0].isAnimating();
	const explicit = made[1].isAnimating() && made[1].get() < 1;
	dispose();
	assert preferred === 1 && reduced, "the preference jumps to the end: " + preferred.toString();
	assert explicit, "an explicit policy animates";
}

function fadeTo(node: HostNode, to: float64): MotionPlayer {
	const doc = documentOf([ramp("box", "opacity", to)]);
	return browserPlayer(doc, [{ slot: "box", node }], [], paused());
}

test "a second player on one element's opacity replaces the first's browser animation with no jump" {
	const node = mount();
	const el = dom(node);
	const older = fadeTo(node, 1);
	older.seek(500);
	assert near(opacity(el), 0.5, 1e-3), computed(el, "opacity");
	assert el.getAnimations().length === 1;
	const newer = fadeTo(node, 0.2);
	newer.seek(250);
	assert el.getAnimations().length === 1, "the older animation is gone: " +
		el.getAnimations().length.toString();
	assert near(opacity(el), 0.05, 1e-3), computed(el, "opacity");
	assert older.cancelled, "the older player holds nothing and is cancelled";
	newer.dispose();
	assert near(opacity(el), 0.05, 1e-3), "dispose commits the shown value: " +
		computed(el, "opacity");
	older.dispose();
	el.remove();
}

test "cancel on a removed element drops the animation and keeps no inline value" {
	const node = mount();
	const el = dom(node);
	const player = fadeAndSlide(node, paused());
	player.seek(400);
	el.remove();
	player.cancel();
	assert el.getAnimations().length === 0, "cancel removes the animations";
	assert el.style.opacity === "", "nothing committed: " + el.style.opacity;
	player.dispose();
}

test "a connected element that refuses commitStyles fails the cancel loudly" {
	const node = mount();
	const el = dom(node);
	const player = fadeAndSlide(node, paused());
	player.seek(400);
	el.style.display = "none";
	let message = "";
	try { player.cancel(); } catch (e) { message = e.message; }
	assert message.startsWith("motion: the browser refused to commit opacity"), message;
	assert el.getAnimations().length === 0, "every animation is cancelled before the throw";
	el.remove();
}

test "translateX and translateY on one element run as one translate animation" {
	const node = mount();
	const el = dom(node);
	const doc = documentOf(
		[ramp("box", "translateX", 100), ramp("box", "translateY", 40)],
	);
	const player = browserPlayer(doc, [{ slot: "box", node }], [], paused());
	player.seek(250);
	assert el.getAnimations().length === 1, "one animation: " +
		el.getAnimations().length.toString();
	assert computed(el, "translate") === "25px 10px", computed(el, "translate");
	player.seek(1000);
	assert computed(el, "translate") === "100px 40px", computed(el, "translate");
	player.cancel();
	assert el.style.translate === "100px 40px", "both axes committed: " +
		el.style.translate;
	player.dispose();
	el.remove();
}

function staggered(): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [
			{
				id: "main",
				duration: 1000,
				tracks: [],
				placements: [
					{ clip: "fade", start: 0, rate: 1, slots: [{ from: "box", to: "first" }] },
					{ clip: "fade", start: 300, rate: 1, slots: [{ from: "box", to: "second" }] },
				],
				labels: [],
			},
			{
				id: "fade",
				duration: 500,
				tracks: [
					{
						slot: "box",
						property: "opacity",
						kind: numberValue(0).kind,
						keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", 500, 1)],
					},
				],
				placements: [],
				labels: [],
			},
		],
	};
}

test "a staggered placement runs on WAAPI with its start as the delay" {
	const firstNode = mount();
	const secondNode = mount();
	const first = dom(firstNode);
	const second = dom(secondNode);
	const player = browserPlayer(
		staggered(),
		[{ slot: "first", node: firstNode }, { slot: "second", node: secondNode }],
		[],
		paused(),
	);
	player.seek(100);
	assert near(opacity(first), 0.2, 1e-3), computed(first, "opacity");
	assert second.getAnimations().length === 0 && opacity(second) === 1,
		"before its start the second element keeps its own value";
	player.seek(400);
	assert first.getAnimations().length === 1 &&
		second.getAnimations().length === 1, "both on WAAPI";
	assert second.style.opacity === "", "no inline write";
	assert near(opacity(first), 0.8, 1e-3) && near(opacity(second), 0.2, 1e-3),
		computed(first, "opacity") + " " + computed(second, "opacity");
	player.seek(100);
	assert near(opacity(second), 0, 1e-3), "a reached placement holds its first key: " +
		computed(second, "opacity");
	player.play();
	await sleepAsync(450);
	assert opacity(second) > 0.2 && opacity(second) < 0.9, "the second plays: " +
		computed(second, "opacity");
	player.dispose();
	first.remove();
	second.remove();
}

function translateX(el: HTMLElement): float64 {
	const text = computed(el, "translate");
	return text === "none" ? 0 : parseFloat(text);
}

test "an element-bound spring runs as one WAAPI linear() animation with no style write from JS in flight" {
	const node = mount();
	const el = dom(node);
	const value = boxValue(0, new MotionPolicy(), node, "translateX");
	let ended = "";
	value.animate(spring(100), (finished: boolean): void => {
		ended = finished ? "finished" : "interrupted";
	});
	assert el.getAnimations().length === 1 && value.handedOver, "handed to WAAPI";
	assert firstEasing(el).startsWith("linear("), firstEasing(el);
	const writes = new StyleWrites();
	const stop = watchStyle(el, writes);
	await sleepAsync(200);
	stop();
	assert writes.count === 0, "style writes in flight: " + writes.count.toString();
	assert translateX(el) > 5 && translateX(el) < 100, computed(el, "translate");
	assert near(value.get(), translateX(el), 0.5), "the closed form tracks the browser: " +
		value.get().toString() + " vs " + computed(el, "translate");
	await sleepAsync(3000);
	assert ended === "finished", ended;
	assert el.getAnimations().length === 0, "the finished animation is gone";
	assert el.style.translate === "100px", "the end value is inline: " + el.style.translate;
	value.dispose();
	el.remove();
}

test "a retarget samples position and velocity, cancels and starts a new sampled spring" {
	const node = mount();
	const el = dom(node);
	const value = boxValue(0, new MotionPolicy(), node, "translateX");
	value.animate(spring(100));
	await sleepAsync(120);
	const before = translateX(el);
	const moving = value.velocity();
	value.animate(spring(200));
	const after = translateX(el);
	assert near(before, after, 0.5), "no jump: " + before.toString() + " -> " + after.toString();
	assert moving > 0 && near(value.velocity(), moving, 1e-6),
		"the spring keeps its velocity: " + moving.toString() + " -> " + value.velocity().toString();
	assert el.getAnimations().length === 1 && value.handedOver, "one new animation";
	await sleepAsync(60);
	assert translateX(el) > after && near(value.get(), translateX(el), 0.5),
		"the new spring runs on: " + computed(el, "translate");
	value.dispose();
	assert el.getAnimations().length === 0;
	el.remove();
}

test "an element-bound timing runs as one WAAPI animation, linear by keyword and any other easing as a sampled linear()" {
	const node = mount();
	const el = dom(node);
	const value = boxValue(0, new MotionPolicy(), node, "translateX");
	value.animate(timing(100, { duration: 400, easing: Easing.linear }));
	assert value.handedOver && firstEasing(el) === "linear", firstEasing(el);
	await sleepAsync(150);
	assert near(value.get(), translateX(el), 0.5), value.get().toString() + " vs " + computed(el, "translate");
	value.animate(timing(100, { duration: 800, easing: Easing.linear }));
	assert value.handedOver && near(value.get(), translateX(el), 0.5),
		"a timing to the same end keeps its start: " + value.get().toString() + " vs " + computed(el, "translate");
	const other = mount();
	const eased = boxValue(0, new MotionPolicy(), other, "opacity");
	eased.animate(timing(1, { duration: 300 }));
	assert eased.handedOver && firstEasing(dom(other)).startsWith("linear("), firstEasing(dom(other));
	await sleepAsync(120);
	assert near(eased.get(), opacity(dom(other)), 0.01), eased.get().toString() + " vs " + computed(dom(other), "opacity");
	await sleepAsync(900);
	assert !value.handedOver && el.style.translate === "100px", el.style.translate;
	assert !eased.handedOver && dom(other).style.opacity === "1", dom(other).style.opacity;
	value.dispose();
	eased.dispose();
	el.remove();
	dom(other).remove();
}

test "a spring that starts on its target, reduced motion and decay hand nothing to WAAPI" {
	const node = mount();
	const el = dom(node);
	const value = boxValue(0, new MotionPolicy(), node, "translateX");
	let ended = false;
	value.animate(spring(0), (finished: boolean): void => { ended = finished; });
	assert ended && !value.handedOver && el.getAnimations().length === 0, "no motion";
	const reduced = boxValue(0, new MotionPolicy(true), node, "opacity");
	reduced.animate(spring(0.5));
	assert !reduced.handedOver && el.style.opacity === "0.5", el.style.opacity;
	value.animate(decay(decayConfig(), 400));
	assert !value.handedOver && el.getAnimations().length === 0, "decay stays on the evaluator";
	await sleepAsync(100);
	assert translateX(el) > 0 && el.style.translate !== "", "the evaluator writes inline: " +
		el.style.translate;
	value.dispose();
	reduced.dispose();
	el.remove();
}

test "an element-bound value on a slot inside a Show animates the remounted element and leaves the removed one" {
	const signals = new MotionSignals();
	signals.number("box", "translateX", 0);
	const [present, setPresent] = createSignal(true);
	const outer: HostNode[] = [];
	const made: AnimatedValue[] = [];
	const dispose = createRoot((dispose: () => void): () => void => {
		const ref = signals.ref("box");
		made.push(useAnimatedValue(0, new MotionPolicy(), signals.target("box", "translateX"))[1]);
		element(<View ref={(h: ViewHandle): void => { outer.push(h.node); }} style={{ width: 100 }}>
			<Show when={present()}>
				<View ref={ref} style={[{ width: 40, height: 40, backgroundColor: "#333" }, signals.style("box")]} />
			</Show>
		</View>)(domHost(), documentBody(), null);
		return dispose;
	});
	const value = made[0];
	const first = dom(signals.elements.node("box") as HostNode);
	value.animate(timing(100, { duration: 600, easing: Easing.linear }));
	assert first.getAnimations().length === 1, "handed to WAAPI on the first element";
	await sleepAsync(150);
	setPresent(false);
	await renderedFrames();
	assert signals.elements.node("box") === null, "the slot names no element while unmounted";
	const left = first.style.translate;
	await sleepAsync(100);
	setPresent(true);
	await renderedFrames();
	const second = dom(signals.elements.node("box") as HostNode);
	const mid = translateX(second);
	assert mid > 30 && mid < 100, "the remounted element shows the running value: " + computed(second, "translate");
	await sleepAsync(700);
	assert translateX(second) === 100, "the remounted element ends on the target: " + computed(second, "translate");
	assert first.getAnimations().length === 0 && first.style.translate === left,
		"the removed element keeps no animation and no later write: " + first.style.translate;
	dispose();
	dom(outer[0]).remove();
}

test "a player claiming an element-bound spring's property replaces its browser animation" {
	const node = mount();
	const el = dom(node);
	const value = boxValue(0, new MotionPolicy(), node, "opacity");
	value.animate(spring(1));
	await sleepAsync(80);
	assert value.handedOver && el.getAnimations().length === 1;
	const player = fadeTo(node, 0.2);
	player.seek(500);
	assert !value.handedOver && !value.isAnimating(), "the value lost its target";
	assert el.getAnimations().length === 1 && near(opacity(el), 0.1, 1e-3),
		computed(el, "opacity");
	player.dispose();
	value.dispose();
	el.remove();
}

test "a fully handed-over player asks for no animation frame while it plays, and still reports its events" {
	const node = mount();
	const el = dom(node);
	const frames = new FrameCount();
	const restore = countFrames(frames);
	const player = fadeAndSlide(
		node,
		{
			...motionOptions(frameClock()),
			repeat: 1,
			timeScale: 4,
		},
	);
	let repeated = 0;
	let completed = 0;
	player.onRepeat = (): void => { repeated += 1; };
	player.onComplete = (): void => { completed += 1; };
	await sleepAsync(60);
	const started = frames.count;
	const writes = new StyleWrites();
	const stop = watchStyle(el, writes);
	await sleepAsync(300);
	stop();
	assert frames.count === started, "frames while playing: " +
		(frames.count - started).toString();
	assert writes.count === 0, "style writes: " + writes.count.toString();
	assert repeated === 1, "repeat " + repeated.toString();
	await sleepAsync(300);
	assert completed === 1 && opacity(el) === 1, "completed " + completed.toString();
	assert near(player.time, 1000, 1e-9), "the playhead reached the end";
	restore();
	player.dispose();
	el.remove();
}

test "a player with an evaluated track keeps its frame loop" {
	const node = mount();
	const el = dom(node);
	const frames = new FrameCount();
	const restore = countFrames(frames);
	const recorder = new Recorder();
	const player = browserPlayer(
		documentOf([ramp("box", "opacity", 1), ramp("box", "progress", 1)]),
		[{ slot: "box", node }],
		[recorder.binding()],
		motionOptions(frameClock()),
	);
	await sleepAsync(300);
	assert frames.count > 5, "frames: " + frames.count.toString();
	restore();
	player.dispose();
	el.remove();
}

test "the showcase plays its staggered entrance and its like spring through WAAPI" {
	const frames = new FrameCount();
	const restore = countFrames(frames);
	const dispose = render(
		element(<MotionShowcase policy={new MotionPolicy()} />),
		domHost(),
		documentBody(),
	);
	await sleepAsync(160);
	const first = byText("card first");
	const second = byText("card second");
	assert first.getAnimations().length === 3 && second.getAnimations().length === 3,
		"cards on WAAPI: " + first.getAnimations().length.toString() + " " +
			second.getAnimations().length.toString();
	const writes = new StyleWrites();
	const stop = watchStyle(second, writes);
	const started = frames.count;
	await sleepAsync(150);
	stop();
	assert writes.count === 0, "style writes in the entrance: " + writes.count.toString();
	assert frames.count === started, "frames in the entrance: " +
		(frames.count - started).toString();
	await sleepAsync(300);
	assert bodyText().includes("entered"), bodyText();
	assert opacity(first) === 1 && opacity(second) === 1;
	const like = byText("like");
	clickOn(like);
	await sleepAsync(50);
	assert like.getAnimations().length === 1 && firstEasing(like).startsWith("linear("),
		"like spring on WAAPI: " + firstEasing(like);
	restore();
	dispose();
}
