import { cancelFrame, frameNow, requestFrame } from "../animation/frame";
import { onCleanup } from "../core/cleanup";
import { getOwner } from "../core/runtime";
import { Accessor, createSignal } from "../core/signal";
import { Clock } from "./clock";
import { MotionColor, MotionDocument, MotionValue, ValueKind, numberValue } from "./document";
import { MotionBinding, MotionOptions, MotionPlayer, motionOptions } from "./player";
import { MotionPolicy } from "./policy";
import { AnimatedValue } from "./value";

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
	const player = new MotionPlayer(doc, bindings, options ?? motionOptions(neonClock()));
	onCleanup((): void => {
		if (!player.disposed) { player.dispose(); }
	});
	return player;
}

export function useAnimatedValue(
	initial: float64,
	policy: MotionPolicy = new MotionPolicy(),
): [Accessor<float64>, AnimatedValue] {
	requireOwner("useAnimatedValue");
	const value = new AnimatedValue(initial, neonClock(), policy);
	const [read, write] = createSignal<float64>(initial);
	value.subscribe((next: float64): void => { write(next); });
	onCleanup((): void => { if (!value.disposed) { value.dispose(); } });
	return [read, value];
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

	number(slot: string, property: string, initial: float64): Accessor<float64> {
		const [read, write] = createSignal<float64>(initial);
		let current = initial;
		this.bindings.push({
			slot,
			property,
			write: (value: MotionValue): void => {
				requireKind(value, ValueKind.Number, slot, property);
				current = value.number;
				write(value.number);
			},
			read: (): MotionValue => numberValue(current),
		});
		return read;
	}

	color(slot: string, property: string, initial: MotionValue): Accessor<string> {
		requireKind(initial, ValueKind.Color, slot, property);
		const [read, write] = createSignal<string>(cssColor(initial.color));
		let current = initial;
		this.bindings.push({
			slot,
			property,
			write: (value: MotionValue): void => {
				requireKind(value, ValueKind.Color, slot, property);
				current = value;
				write(cssColor(value.color));
			},
			read: (): MotionValue => current,
		});
		return read;
	}
}
