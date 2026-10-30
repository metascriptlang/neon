import { Accessor, createSignal } from "../../src/core/signal";
import { onSettled } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { For } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable } from "../../src/components/primitives";
import {
	MotionClip,
	MotionDocument,
	MotionKeyframe,
	MotionSlotMapping,
	ValueKind,
	colorValue,
	linearKeyframe,
	spring,
	stagger,
	staggerOptions,
} from "../../src/motion/index";
import { MotionPolicy } from "../../src/motion/policy";
import { MotionSignals, useAnimatedValue, useMotion } from "../../src/motion/neon";

export const CARD_SLOTS: string[] = ["first", "second"];
export const CARD_ENTRANCE_MS: float64 = 300;
export const CARD_STAGGER_MS: float64 = 120;
export const CARD_RISE_PX: float64 = 24;
export const LIKED_SCALE: float64 = 1.2;

const styles = createStyles({
	screen: { flex: 1, flexDirection: "column", gap: 12, padding: 16, backgroundColor: "#1e1e2e" },
	card: { height: 72, padding: 12, justifyContent: "center" },
	title: { color: "#11111b", fontSize: 16 },
	like: { padding: 10, backgroundColor: "#f38ba8", alignSelf: "flex-start" },
	label: { color: "#11111b", fontSize: 14 },
});

function cardEntrance(): MotionClip {
	const dim: MotionKeyframe = { ...linearKeyframe("c0", 0, 0), value: colorValue(0.27, 0.28, 0.35, 1) };
	const lit: MotionKeyframe = {
		...linearKeyframe("c1", CARD_ENTRANCE_MS, 0),
		value: colorValue(0.65, 0.89, 0.63, 1),
	};
	return {
		id: "cardIn",
		duration: CARD_ENTRANCE_MS,
		tracks: [
			{
				slot: "card",
				property: "opacity",
				kind: ValueKind.Number,
				keyframes: [linearKeyframe("o0", 0, 0), linearKeyframe("o1", CARD_ENTRANCE_MS, 1)],
			},
			{
				slot: "card",
				property: "translateY",
				kind: ValueKind.Number,
				keyframes: [
					linearKeyframe("y0", 0, CARD_RISE_PX),
					linearKeyframe("y1", CARD_ENTRANCE_MS, 0),
				],
			},
			{ slot: "card", property: "backgroundColor", kind: ValueKind.Color, keyframes: [dim, lit] },
		],
		placements: [],
		labels: [],
	};
}

export function entranceDocument(): MotionDocument {
	const slots = CARD_SLOTS.map((name: string): MotionSlotMapping[] => [{ from: "card", to: name }]);
	return {
		version: 1,
		root: "screen",
		clips: [
			{
				id: "screen",
				duration: CARD_STAGGER_MS * ((CARD_SLOTS.length - 1) as float64) + CARD_ENTRANCE_MS,
				tracks: [],
				placements: stagger("cardIn", 1, slots, staggerOptions(CARD_STAGGER_MS)),
				labels: [],
			},
			cardEntrance(),
		],
	};
}

interface CardMotion {
	slot: string;
	opacity: Accessor<float64>;
	rise: Accessor<float64>;
	background: Accessor<string>;
}

export function MotionShowcase(props: { policy: MotionPolicy }): NeonNode {
	const signals = new MotionSignals();
	const cards = CARD_SLOTS.map((slot: string): CardMotion => ({
		slot,
		opacity: signals.number(slot, "opacity", 0),
		rise: signals.number(slot, "translateY", CARD_RISE_PX),
		background: signals.color(slot, "backgroundColor", colorValue(0.27, 0.28, 0.35, 1)),
	}));
	const [entered, setEntered] = createSignal(false);
	const entrance = useMotion(entranceDocument(), signals.bindings);
	entrance.onComplete = (): void => { setEntered(true); };
	if (props.policy.reducedMotion) {
		onSettled((): Cleanup | null => {
			entrance.finish();
			return null;
		});
	}

	const [scale, likeScale] = useAnimatedValue(1, props.policy);
	const [liked, setLiked] = createSignal(false);
	const toggleLike = (e: NeonEvent): void => {
		const next = !liked();
		setLiked(next);
		likeScale.animate(spring(next ? LIKED_SCALE : 1));
	};

	return <View style={styles.screen}>
		<Text style={styles.label}>{(entered() ? "entered" : "entering") + " · " + (liked() ? "liked" : "not liked")}</Text>
		<For each={cards}>{(card: CardMotion): NeonNode => <View style={[styles.card, {
			opacity: card.opacity(),
			transform: `translateY(${card.rise()}px)`,
			backgroundColor: card.background(),
		}]}>
			<Text style={styles.title}>{"card " + card.slot}</Text>
		</View>}</For>
		<Pressable onPress={toggleLike}>
			<View style={[styles.like, { transform: `scale(${scale()})` }]}>
				<Text style={styles.label}>like</Text>
			</View>
		</Pressable>
	</View>;
}
