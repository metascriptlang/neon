import { ScrollAxis, ScrollSource, scrollSource } from "pulse/src/scroll";
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
	elementValue,
	frameClock,
	motionElements,
} from "../../src/motion/waapi";
import { MotionPolicy } from "pulse/src/policy";
import { MotionShowcase } from "../../examples/motionShowcase/showcase";
import { decay, spring } from "pulse/src/value";
import { decayConfig } from "pulse/src/decay";

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

extern function firstEasing(el: HTMLElement): string from
	"(el => { const a = el.getAnimations(); return a.length === 0 ? '' : a[0].effect.getKeyframes()[0].easing; })(#)";

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

test "a View's opacity and translate run as WAAPI animations with no inline writes" {
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
	assert el.style.opacity === "", "no inline write at the end: " +
		el.style.opacity;
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

test "a player on a scroll source is refused at construction rather than run its WAAPI tracks on time" {
	const node = mount();
	const scroller: ScrollSource = {
		offset: (axis: ScrollAxis): float64 => 0,
		max: (axis: ScrollAxis): float64 => 100,
		viewport: (axis: ScrollAxis): float64 => 50,
	};
	let message = "";
	try {
		fadeAndSlide(node, { ...paused(), source: scrollSource(scroller) });
	} catch (e) { message = e.message; }
	assert message === "motion: an element player runs on time; WAAPI takes no scroll or view source yet", message;
	dom(node).remove();
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
