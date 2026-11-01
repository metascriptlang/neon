import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { element } from "../macros/ui/element";
import { Show } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { Style } from "../render/style";
import { View } from "../components/primitives";
import { Easing } from "pulse/src/easing";
import { timing } from "pulse/src/value";
import { useAnimatedValue } from "./neon";

export type PresenceType = "fade" | "scale" | "slide-up" | "slide-down" | "slide-left" | "slide-right";

export interface PresenceProps {
	when: Accessor<boolean>;
	type?: Accessor<PresenceType> | null;
	duration?: Accessor<number> | null;
	distance?: Accessor<number> | null;
	style?: Accessor<Style> | null;
	onEntered?: (() => void) | null;
	onExited?: (() => void) | null;
	children?: NeonNode | null;
}

function slideTransform(type: PresenceType, offset: number): string {
	return match (type) {
		"slide-up" => `translateY(${offset}px)`,
		"slide-down" => `translateY(${-offset}px)`,
		"slide-left" => `translateX(${offset}px)`,
		"slide-right" => `translateX(${-offset}px)`,
		"scale" => `scale(${1 - offset / 100})`,
		_ => "none",
	};
}

// Flutter's AnimatedSwitcher / Reanimated's entering-exiting for one child: the
// child stays mounted until its exit animation ends.
export function Presence(props: PresenceProps): NeonNode {
	const { when, type, duration, distance, style, onEntered, onExited } = props;
	const initial = untrack((): boolean => when());
	const [progress, value] = useAnimatedValue(initial ? 1 : 0);
	const [mounted, setMounted] = createSignal(initial);
	const kind = (): PresenceType => type === null ? "fade" : (type as Accessor<PresenceType>)();
	const ms = (): number => duration === null ? 220 : (duration as Accessor<number>)();
	const span = (): number => distance === null ? 24 : (distance as Accessor<number>)();
	createRenderEffect<boolean>(
		(prev: boolean | null): boolean => when(),
		(show: boolean, prev: boolean | null): Cleanup | null => {
			if (show) { setMounted(true); }
			const easing = show ? Easing.out(Easing.cubic) : Easing.in(Easing.cubic);
			value.animate(timing(show ? 1 : 0, { duration: ms(), easing }), (finished: boolean): void => {
				if (!finished) { return; }
				if (show) {
					if (onEntered !== null) { (onEntered as () => void)(); }
				} else {
					setMounted(false);
					if (onExited !== null) { (onExited as () => void)(); }
				}
			});
			return null;
		},
		{ defer: true },
	);
	const box = accessor((): Style => {
		const p = progress();
		const base: Style = style === null ? {} : (style as Accessor<Style>)();
		const t = kind();
		const offset = t === "scale" ? (1 - p) * 10 : (1 - p) * span();
		return { ...base, opacity: p, transform: slideTransform(t, offset) };
	});
	const child = props.children;
	return element(<Show when={mounted()}><View style={box}>{child}</View></Show>);
}
