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
} from "../../src/motion/document";
import {
	MotionBinding,
	MotionOptions,
	motionOptions,
} from "../../src/motion/player";
import { BrowserMotionPlayer, frameClock } from "../../src/motion/waapi";

extern class Animation {}

extern class CSSStyleDeclaration {
	opacity: string;
	translate: string;
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
): BrowserMotionPlayer {
	const doc = documentOf(
		[ramp("box", "opacity", 1), ramp("box", "translateX", 100)],
	);
	return new BrowserMotionPlayer(
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
	const player = new BrowserMotionPlayer(
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
		new BrowserMotionPlayer(
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
		new BrowserMotionPlayer(
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

function fadeTo(node: HostNode, to: float64): BrowserMotionPlayer {
	const doc = documentOf([ramp("box", "opacity", to)]);
	return new BrowserMotionPlayer(doc, [{ slot: "box", node }], [], paused());
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
