import { cancelFrame, frameNow, requestFrame } from "../animation/frame";
import { onCleanup } from "../core/cleanup";
import { getOwner } from "../core/runtime";
import { Accessor, createSignal } from "../core/signal";
import { Clock } from "pulse/src/clock";
import { MotionColor, MotionDocument, MotionValue, ValueKind, numberValue } from "pulse/src/document";
import { MotionBinding, MotionOptions, MotionPlayer, motionOptions } from "pulse/src/player";
import { MotionPolicy } from "pulse/src/policy";
import { Composition, MotionTarget } from "pulse/src/target";
import { AnimatedValue } from "pulse/src/value";
import { ViewHandle } from "../components/primitives";
import { HostNode } from "../render/hostTypes";
import { Style } from "../render/style";
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
	return {
		now: (): float64 => frameNow(),
		request: (callback: (time: float64) => void): int32 => {
			const ticket = new FrameTicket();
			ticket.id = requestFrame((time: float64): void => {
				const index = live.indexOf(ticket);
				if (index < 0) { return; }
				live.splice(index, 1);
				callback(time);
			});
			live.push(ticket);
			return ticket.id;
		},
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
	policy: MotionPolicy = new MotionPolicy(),
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
	const [read, write] = createSignal<float64>(initial);
	const reach = target?.write ?? null;
	const shown = driven ? null : own;
	value.subscribe((next: float64): void => {
		write(next);
		if (reach !== null) { reach(numberValue(next)); }
		if (shown !== null) { shown.signals.show(shown.slot, shown.property, numberValue(next)); }
	});
	onCleanup((): void => { if (!value.disposed) { value.dispose(); } });
	return [read, value];
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

class OwnedSlot {
	slot: string;
	owned: Accessor<boolean>;
	own: (owned: boolean) => void;
	node: HostNode | null = null;

	constructor(slot: string, initial: boolean) {
		this.slot = slot;
		const [owned, setOwned] = createSignal(initial, { ownedWrite: true });
		this.owned = owned;
		this.own = (next: boolean): void => { setOwned(next); };
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
		const [read, write] = createSignal<float64>(initial);
		let current = initial;
		this.styles.push(
			new SlotStyle(slot, property, (): string => "", (): float64 => read()),
		);
		this.bind(
			slot,
			property,
			(value: MotionValue): void => {
				requireKind(value, ValueKind.Number, slot, property);
				current = value.number;
				write(value.number);
			},
			(): MotionValue => numberValue(current),
		);
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
			this.elements.set(slot, handle.node);
			const motion = elementMotion;
			const owns = motion !== null && motion.owns(handle.node);
			owned.node = owns ? handle.node : null;
			owned.own(owns);
			for (const binding of this.bindings) {
				const read = binding.read;
				if (binding.slot === slot && read !== null) { this.show(slot, binding.property, read()); }
			}
		};
	}

	style(slot: string): Style {
		const style: Style = {};
		const owned = this.ownedSlot(slot).owned();
		const motion = elementMotion;
		const shows = (property: string): boolean =>
			!owned || motion === null || !motion.carries(property);
		const parts: string[] = [];
		for (const property of TRANSFORM_ORDER) {
			for (const entry of this.styles) {
				if (entry.slot === slot && entry.property === property && shows(property)) {
					parts.push(transformPart(property, entry.number()));
				}
			}
		}
		if (parts.length > 0) { style.transform = parts.join(" "); }
		for (const entry of this.styles) {
			if (entry.slot !== slot || !shows(entry.property)) { continue; }
			match (entry.property) {
				"opacity" => { style.opacity = entry.number(); },
				"width" => { style.width = entry.number(); },
				"height" => { style.height = entry.number(); },
				"left" => { style.left = entry.number(); },
				"top" => { style.top = entry.number(); },
				"right" => { style.right = entry.number(); },
				"bottom" => { style.bottom = entry.number(); },
				"borderRadius" => { style.borderRadius = entry.number(); },
				"backgroundColor" => { style.backgroundColor = entry.text(); },
				"color" => { style.color = entry.text(); },
				"borderColor" => { style.borderColor = entry.text(); },
				_ => {},
			};
		}
		return style;
	}

	show(slot: string, property: string, value: MotionValue): void {
		const node = this.ownedSlot(slot).node;
		const motion = elementMotion;
		if (node !== null && motion !== null && motion.carries(property)) {
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
	): void {
		const target = new SignalTarget(this, slot, property, read, write);
		this.bindings.push({ slot, property, write, read, target });
	}
}
