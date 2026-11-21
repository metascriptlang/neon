import { cancelFrame, frameNow, requestFrame, requestFrameAt } from "../animation/frame";
import { onCleanup } from "../core/cleanup";
import { getObserver, getOwner } from "../core/runtime";
import { Accessor, Setter, accessor, createSignal, untrack } from "../core/signal";
import { Clock } from "pulse/src/clock";
import { MotionColor, MotionDocument, MotionValue, ValueKind, numberValue } from "pulse/src/document";
import { MotionBinding, MotionOptions, MotionPlayer, motionOptions } from "pulse/src/player";
import { MotionPolicy } from "pulse/src/policy";
import { Composition, MotionTarget } from "pulse/src/target";
import { AnimatedValue } from "pulse/src/value";
import { ViewHandle } from "../components/primitives";
import { HostNode } from "../render/hostTypes";
import { ClaimMark, Style, StyleClaim, StyleValue } from "../render/style";
import { MotionElements } from "./waapi";

export interface ElementMotion {
	owns: (node: HostNode) => boolean;
	carries: (property: string) => boolean;
	player: (
		doc: MotionDocument,
		elements: MotionElements,
		bindings: MotionBinding[],
		options: MotionOptions,
	) => MotionPlayer;
	value: (
		initial: float64,
		policy: MotionPolicy,
		elements: MotionElements,
		slot: string,
		property: string,
		target: MotionTarget | null,
	) => AnimatedValue;
	show: (node: HostNode, property: string, value: MotionValue) => void;
	claimsAhead: () => boolean;
}

when (js) {
	import { browserMotionPlayer, browserOwns, elementValue, showStyle, styleProperty } from "./waapi";

	extern function documentPresent(): boolean from "(typeof document !== 'undefined')";
	extern function prefersReducedMotion(): boolean from
		"(typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches)";

	export function hostMotionPolicy(): MotionPolicy {
		return new MotionPolicy(prefersReducedMotion());
	}

	function platformMotion(): ElementMotion | null {
		return {
			owns: browserOwns,
			carries: (property: string): boolean => styleProperty(property) !== null,
			player: browserMotionPlayer,
			value: elementValue,
			show: showStyle,
			claimsAhead: (): boolean => documentPresent(),
		};
	}
} else {
	import { layerChannel, nativeElementValue, nativeMotionPlayer, nativeOwns, showLayer } from "./native";
	import { layerEngine } from "../platform/native/layerEngine";

	export function hostMotionPolicy(): MotionPolicy {
		return new MotionPolicy();
	}

	function platformMotion(): ElementMotion | null {
		return {
			owns: nativeOwns,
			carries: (property: string): boolean => layerChannel(property) !== null,
			player: nativeMotionPlayer,
			value: nativeElementValue,
			show: showLayer,
			claimsAhead: (): boolean => layerEngine() !== null,
		};
	}
}

let elementMotion: ElementMotion | null = platformMotion();

export function installElementMotion(motion: ElementMotion | null): void {
	elementMotion = motion;
}

class FrameTicket {
	id: int32 = 0;
}

export function neonClock(): Clock {
	const live: FrameTicket[] = [];
	const ticketed = (
		issue: (fire: (time: float64) => void) => int32,
		callback: (time: float64) => void,
	): int32 => {
		const ticket = new FrameTicket();
		ticket.id = issue((time: float64): void => {
			const index = live.indexOf(ticket);
			if (index < 0) { return; }
			live.splice(index, 1);
			callback(time);
		});
		live.push(ticket);
		return ticket.id;
	};
	return {
		now: (): float64 => frameNow(),
		request: (callback: (time: float64) => void): int32 =>
			ticketed((fire: (time: float64) => void): int32 => requestFrame(fire), callback),
		requestAt: (time: float64, callback: (time: float64) => void): int32 =>
			ticketed((fire: (time: float64) => void): int32 => requestFrameAt(time, fire), callback),
		cancel: (id: int32): void => {
			for (let i: int32 = 0; i < live.length; i += 1) {
				if (live[i].id === id) {
					live.splice(i, 1);
					break;
				}
			}
			cancelFrame(id);
		},
	};
}

function requireOwner(what: string): void {
	if (getOwner() === null) {
		throw new Error(
			"motion: " + what + " outside an owner would never be disposed; " +
				"call it in a component or under createRoot",
		);
	}
}

export function useMotion(
	doc: MotionDocument,
	bindings: MotionBinding[],
	options: MotionOptions | null = null,
): MotionPlayer {
	requireOwner("useMotion");
	const chosen = options ?? motionOptions(neonClock());
	const elements = elementsOf(bindings);
	const motion = elementMotion;
	const player = elements !== null && motion !== null
		? motion.player(doc, elements, bindings, chosen)
		: new MotionPlayer(doc, bindings, chosen);
	onCleanup((): void => {
		if (!player.disposed) { player.dispose(); }
	});
	return player;
}

export function useAnimatedValue(
	initial: float64,
	policy: MotionPolicy = hostMotionPolicy(),
	target: MotionTarget | null = null,
	composition: Composition = Composition.Replace,
): [Accessor<float64>, AnimatedValue] {
	requireOwner("useAnimatedValue");
	const own = bindSignalTarget(target);
	const motion = elementMotion;
	const driven = own !== null && motion !== null && composition === Composition.Replace;
	const value = driven
		? motion.value(initial, policy, own.signals.elements, own.slot, own.property, own)
		: new AnimatedValue(initial, neonClock(), policy, target, composition);
	const reach = target?.write ?? null;
	if (driven) {
		const demand = new ValueDemand(value);
		const read = demand.reader(initial, reach);
		own.watch.attach(demand);
		onCleanup((): void => {
			own.watch.detach(demand);
			demand.release();
			if (!value.disposed) { value.dispose(); }
		});
		return [read, value];
	}
	const reading = new LazySignal(initial);
	const read = accessor((): float64 => reading.read());
	value.subscribe((next: float64): void => {
		reading.write(next);
		if (reach !== null) { reach(numberValue(next)); }
		if (own !== null) { own.signals.show(own.slot, own.property, numberValue(next)); }
	});
	onCleanup((): void => { if (!value.disposed) { value.dispose(); } });
	return [read, value];
}

let quietReads: int32 = 0;

function quietly<T>(read: () => T): T {
	quietReads += 1;
	try {
		return read();
	} finally {
		quietReads -= 1;
	}
}

class Watch {
	private watched: boolean = false;
	private demands: ValueDemand[] = [];

	attach(demand: ValueDemand): void {
		this.demands.push(demand);
		if (this.watched) { demand.enter(); }
	}

	detach(demand: ValueDemand): void {
		const before = this.demands.length;
		this.demands = this.demands.filter((other: ValueDemand): boolean => other !== demand);
		if (this.watched && this.demands.length < before) { demand.leave(); }
	}

	watch(): void {
		if (this.watched) { return; }
		this.watched = true;
		for (const demand of this.demands) { demand.enter(); }
	}

	unwatch(): void {
		if (!this.watched) { return; }
		this.watched = false;
		for (const demand of this.demands) { demand.leave(); }
	}

	flush(): void {
		for (const demand of this.demands) { demand.exact(); }
	}
}

class ValueDemand {
	private value: AnimatedValue;
	private readers: int32 = 0;
	private frames: (() => void) | null = null;
	private hearing: (() => void) | null = null;

	constructor(value: AnimatedValue) {
		this.value = value;
	}

	reader(initial: float64, reach: ((value: MotionValue) => void) | null): Accessor<float64> {
		let watched = false;
		const [tick, set] = createSignal<float64>(initial, {
			unobserved: (): void => {
				if (watched) {
					watched = false;
					this.leave();
				}
			},
		});
		this.hearing = this.value.follow((next: float64): void => {
			if (quietReads === 0) { set(next); }
			if (reach !== null) { reach(numberValue(next)); }
		});
		return accessor((): float64 => {
			if (!watched && getObserver() !== null) {
				watched = true;
				quietly((): void => { this.enter(); });
			}
			tick();
			return this.exact();
		});
	}

	enter(): void {
		this.readers += 1;
		if (this.readers === 1 && this.hearing !== null && !this.value.disposed) {
			this.frames = this.value.subscribe((next: float64): void => {});
		}
	}

	leave(): void {
		if (this.readers === 0) { throw new Error("motion: a value demand left more often than it entered"); }
		this.readers -= 1;
		if (this.readers > 0) { return; }
		const frames = this.frames;
		this.frames = null;
		if (frames !== null) { frames(); }
	}

	exact(): float64 {
		return quietly((): float64 => this.value.get());
	}

	release(): void {
		const frames = this.frames;
		const hearing = this.hearing;
		this.frames = null;
		this.hearing = null;
		if (frames !== null) { frames(); }
		if (hearing !== null) { hearing(); }
	}
}

class LazySignal {
	current: float64;
	get: Accessor<float64> | null = null;
	set: Setter<float64> | null = null;

	constructor(initial: float64) {
		this.current = initial;
	}

	read(): float64 {
		if (this.get === null) {
			const [get, set] = createSignal<float64>(this.current);
			this.get = get;
			this.set = set;
		}
		return (this.get as Accessor<float64>)();
	}

	write(next: float64): void {
		this.current = next;
		if (this.set !== null) { (this.set as Setter<float64>)(next); }
	}
}

function bindSignalTarget(target: MotionTarget | null | undefined): SignalTarget | null {
	if (target === null || target === undefined || !(target instanceof SignalTarget)) {
		return null;
	}
	const own = target as SignalTarget;
	own.signals.playerBound = true;
	return own.signals.elements.declared.includes(own.slot) ? own : null;
}

function elementsOf(bindings: MotionBinding[]): MotionElements | null {
	let found: MotionElements | null = null;
	for (const binding of bindings) {
		const own = bindSignalTarget(binding.target);
		if (own === null) { continue; }
		if (found !== null && found !== own.signals.elements) {
			throw new Error(
				"motion: one player binds elements of two MotionSignals; " +
					"name every element slot through one",
			);
		}
		found = own.signals.elements;
	}
	return found;
}

class SignalTarget extends MotionTarget {
	signals: MotionSignals;
	slot: string;
	property: string;
	watch: Watch = new Watch();

	constructor(
		signals: MotionSignals,
		slot: string,
		property: string,
		read: () => MotionValue,
		write: (value: MotionValue) => void,
	) {
		super(read, write);
		this.signals = signals;
		this.slot = slot;
		this.property = property;
	}

}

let nextClaim: int32 = 1;

function readField(field: string): (style: Style) => StyleValue {
	return match (field) {
		"transform" => (style: Style): StyleValue => style.transform,
		"opacity" => (style: Style): StyleValue => style.opacity,
		"width" => (style: Style): StyleValue => style.width,
		"height" => (style: Style): StyleValue => style.height,
		"left" => (style: Style): StyleValue => style.left,
		"top" => (style: Style): StyleValue => style.top,
		"right" => (style: Style): StyleValue => style.right,
		"bottom" => (style: Style): StyleValue => style.bottom,
		"borderRadius" => (style: Style): StyleValue => style.borderRadius,
		"backgroundColor" => (style: Style): StyleValue => style.backgroundColor,
		"color" => (style: Style): StyleValue => style.color,
		"borderColor" => (style: Style): StyleValue => style.borderColor,
		_ => { throw new Error("motion: no style field " + field + " to claim"); },
	};
}

class OwnedSlot {
	slot: string;
	ahead: boolean;
	claims: StyleClaim[] = [];
	owned: Accessor<boolean>;
	own: (owned: boolean) => void;
	node: HostNode | null = null;
	current: HostNode | null = null;
	element: () => HostNode | null;
	place: (node: HostNode | null) => void;

	constructor(slot: string, ahead: boolean) {
		this.slot = slot;
		this.ahead = ahead;
		const [owned, setOwned] = createSignal(ahead, { ownedWrite: true });
		this.owned = owned;
		this.own = (next: boolean): void => { setOwned(next); };
		const [placed, setPlaced] = createSignal<int32>(0, { ownedWrite: true });
		this.element = (): HostNode | null => {
			placed();
			return this.current;
		};
		this.place = (node: HostNode | null): void => {
			this.current = node;
			setPlaced(untrack((): int32 => placed()) + 1);
		};
	}

	claim(field: string, elements: MotionElements): StyleClaim {
		for (const claim of this.claims) {
			if (claim.field === field) { return claim; }
		}
		const slot = this.slot;
		const claim: StyleClaim = {
			id: nextClaim,
			field,
			read: readField(field),
			settle: (won: boolean): void => { elements.yieldField(slot, field, !won); },
		};
		nextClaim += 1;
		this.claims.push(claim);
		return claim;
	}
}

class SlotStyle {
	slot: string;
	property: string;
	text: () => string;
	number: () => float64;

	constructor(
		slot: string,
		property: string,
		text: () => string,
		number: () => float64,
	) {
		this.slot = slot;
		this.property = property;
		this.text = text;
		this.number = number;
	}
}

const TRANSFORM_ORDER: string[] = [
	"translateX",
	"translateY",
	"rotate",
	"scale",
	"scaleX",
	"scaleY",
];

function transformPart(property: string, value: float64): string {
	const unit = property.startsWith("translate")
		? "px"
		: property === "rotate" ? "deg" : "";
	return property + "(" + value.toString() + unit + ")";
}

function requireKind(value: MotionValue, kind: ValueKind, slot: string, property: string): void {
	if (value.kind !== kind) {
		const expected = kind === ValueKind.Number ? "number" : "colour";
		throw new Error("motion: " + slot + "." + property + " is bound as a " + expected);
	}
}

function channel(unit: float64): string {
	return Math.round(Math.min(1, Math.max(0, unit)) * 255).toString();
}

export function cssColor(color: MotionColor): string {
	return "rgba(" + channel(color.r) + ", " + channel(color.g) + ", " + channel(color.b) + ", " +
		color.a.toString() + ")";
}

export class MotionSignals {
	bindings: MotionBinding[] = [];
	elements: MotionElements = new MotionElements();
	playerBound: boolean = false;
	private slots: OwnedSlot[] = [];
	private styles: SlotStyle[] = [];

	number(slot: string, property: string, initial: float64): Accessor<float64> {
		let current = initial;
		const watch = new Watch();
		const [tick, write] = createSignal<float64>(initial, {
			unobserved: (): void => { watch.unwatch(); },
		});
		const shown = (): float64 => quietly((): float64 => {
			watch.flush();
			return current;
		});
		const target = this.bind(
			slot,
			property,
			(value: MotionValue): void => {
				requireKind(value, ValueKind.Number, slot, property);
				current = value.number;
				if (quietReads === 0) { write(value.number); }
			},
			(): MotionValue => numberValue(shown()),
		);
		target.watch = watch;
		const read = accessor((): float64 => {
			if (getObserver() !== null) { quietly((): void => { watch.watch(); }); }
			tick();
			return shown();
		});
		this.styles.push(new SlotStyle(slot, property, (): string => "", read));
		return read;
	}

	color(slot: string, property: string, initial: MotionValue): Accessor<string> {
		requireKind(initial, ValueKind.Color, slot, property);
		const [read, write] = createSignal<string>(cssColor(initial.color));
		let current = initial;
		this.styles.push(
			new SlotStyle(slot, property, (): string => read(), (): float64 => 0),
		);
		this.bind(
			slot,
			property,
			(value: MotionValue): void => {
				requireKind(value, ValueKind.Color, slot, property);
				current = value;
				write(cssColor(value.color));
			},
			(): MotionValue => current,
		);
		return read;
	}

	target(slot: string, property: string): MotionTarget {
		for (const binding of this.bindings) {
			if (binding.slot === slot && binding.property === property) {
				return binding.target as MotionTarget;
			}
		}
		throw new Error("motion: no binding " + slot + "." + property);
	}

	ref(slot: string): (handle: ViewHandle) => void {
		if (this.playerBound) {
			throw new Error(
				"motion: signals.ref(\"" + slot + "\") comes after a player bound these MotionSignals, " +
					"so that player would drive " + slot + " through signals only; " +
					"declare every signals.ref before useMotion or useAnimatedValue",
			);
		}
		this.elements.declare(slot);
		const ahead = elementMotion;
		const owned = this.ownedSlot(slot, ahead !== null && ahead.claimsAhead());
		return (handle: ViewHandle): void => {
			const node = handle.node;
			this.elements.set(slot, node);
			const motion = elementMotion;
			const owns = motion !== null && motion.owns(node);
			owned.node = owns ? node : null;
			owned.own(owns);
			owned.place(node);
			onCleanup((): void => {
				this.elements.clear(slot, node);
				if (owned.current !== node) { return; }
				owned.node = null;
				owned.own(owned.ahead);
				owned.place(null);
			});
			for (const binding of this.bindings) {
				const read = binding.read;
				if (binding.slot === slot && read !== null) { this.show(slot, binding.property, read()); }
			}
		};
	}

	element(slot: string): HostNode | null {
		return this.ownedSlot(slot).element();
	}

	style(slot: string): Style {
		const style: Style = {};
		const owned = this.ownedSlot(slot);
		const motion = elementMotion;
		const claiming = owned.owned() && motion !== null;
		const holds = (property: string): boolean =>
			claiming && (motion as ElementMotion).carries(property);
		const value = (entry: SlotStyle): float64 =>
			holds(entry.property) ? untrack(entry.number) : entry.number();
		const text = (entry: SlotStyle): string =>
			holds(entry.property) ? untrack(entry.text) : entry.text();
		const held: string[] = [];
		const parts: string[] = [];
		for (const property of TRANSFORM_ORDER) {
			for (const entry of this.styles) {
				if (entry.slot === slot && entry.property === property) {
					parts.push(transformPart(property, value(entry)));
					if (holds(property) && !held.includes("transform")) { held.push("transform"); }
				}
			}
		}
		if (parts.length > 0) { style.transform = parts.join(" "); }
		for (const entry of this.styles) {
			if (entry.slot !== slot) { continue; }
			match (entry.property) {
				"opacity" => { style.opacity = value(entry); },
				"width" => { style.width = value(entry); },
				"height" => { style.height = value(entry); },
				"left" => { style.left = value(entry); },
				"top" => { style.top = value(entry); },
				"right" => { style.right = value(entry); },
				"bottom" => { style.bottom = value(entry); },
				"borderRadius" => { style.borderRadius = value(entry); },
				"backgroundColor" => { style.backgroundColor = text(entry); },
				"color" => { style.color = text(entry); },
				"borderColor" => { style.borderColor = text(entry); },
				_ => { continue; },
			};
			if (holds(entry.property)) { held.push(entry.property); }
		}
		if (held.length > 0) {
			style.claims = held.map((field: string): ClaimMark => {
				const claim = owned.claim(field, this.elements);
				return { claim, value: claim.read(style), won: true };
			});
		}
		return style;
	}

	show(slot: string, property: string, value: MotionValue): void {
		const node = this.ownedSlot(slot).node;
		const motion = elementMotion;
		if (node !== null && motion !== null && motion.carries(property) && !this.elements.yields(slot, property)) {
			motion.show(node, property, value);
		}
	}

	private ownedSlot(slot: string, ahead: boolean = false): OwnedSlot {
		for (const owned of this.slots) {
			if (owned.slot === slot) { return owned; }
		}
		const owned = new OwnedSlot(slot, ahead);
		this.slots.push(owned);
		return owned;
	}

	private bind(
		slot: string,
		property: string,
		write: (value: MotionValue) => void,
		read: () => MotionValue,
	): SignalTarget {
		const target = new SignalTarget(this, slot, property, read, write);
		this.bindings.push({ slot, property, write, read, target });
		return target;
	}
}
