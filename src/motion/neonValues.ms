import { onCleanup } from "../core/cleanup";
import { getOwner } from "../core/runtime";
import { Accessor, createSignal } from "../core/signal";
import { NeonEvent } from "../render/event";
import { ValueSource } from "pulse/src/derived";
import { EventMapping, event } from "pulse/src/event";
import { MotionPolicy } from "pulse/src/policy";
import { AnimatedValue } from "pulse/src/value";
import { hostMotionPolicy, neonClock } from "./neon";

export function createAnimatedValue(
	initial: float64,
	policy: MotionPolicy = hostMotionPolicy(),
): [Accessor<float64>, AnimatedValue] {
	const value = new AnimatedValue(initial, neonClock(), policy);
	const [read, write] = createSignal<float64>(initial);
	value.subscribe((next: float64): void => { write(next); });
	return [read, value];
}

export function useValueSignal(source: ValueSource): Accessor<float64> {
	if (getOwner() === null) {
		throw new Error(
			"motion: useValueSignal outside an owner would never unsubscribe; " +
				"call it in a component or under createRoot",
		);
	}
	const [read, write] = createSignal<float64>(source.get());
	onCleanup(source.subscribe((next: float64): void => { write(next); }));
	return read;
}

export function animatedEvent(
	mapping: EventMapping,
	listener: ((e: NeonEvent) => void) | null = null,
): (e: NeonEvent) => void {
	const drive = event(mapping);
	return (e: NeonEvent): void => {
		drive({
			x: e.x,
			y: e.y,
			width: e.width,
			height: e.height,
			contentWidth: e.contentWidth,
			contentHeight: e.contentHeight,
		});
		if (listener !== null) { listener(e); }
	};
}
