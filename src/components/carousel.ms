// react-native-reanimated-carousel's surface over PageView: a loop by default, auto-play
// that pauses while a finger holds the pages, and Flutter carousel_slider's
// viewportFraction for peeking neighbours, which the parallax mode shrinks.

import { Accessor, accessor, untrack } from "../core/signal";
import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { onCleanup } from "../core/cleanup";
import { NeonNode } from "../render/node";
import { Style } from "../render/style";
import { PageController, PageOrientation, PageRenderItemInfo, PageScrollState, PageView } from "./pageView";
import { TimerHandle } from "./timerHandle";

export type CarouselMode = "default" | "parallax";

// react-native-reanimated-carousel: autoPlayInterval 1000 ms; parallax mode
// parallaxScrollingScale 0.8.
const AUTO_PLAY_INTERVAL = 1000;
const PARALLAX_SCALE = 0.8;

export function parallaxScale(delta: number, scale: number): number {
	const distance = Math.min(1, Math.abs(delta));
	return 1 - (1 - scale) * distance;
}

export function Carousel<T>(props: {
	data: Accessor<T[]>;
	renderItem: (info: PageRenderItemInfo<T>) => NeonNode;
	ref?: ((controller: PageController) => void) | null;
	defaultIndex?: Accessor<number> | null;
	loop?: Accessor<boolean> | null;
	autoPlay?: Accessor<boolean> | null;
	autoPlayInterval?: Accessor<number> | null;
	autoPlayReverse?: Accessor<boolean> | null;
	vertical?: Accessor<boolean> | null;
	enabled?: Accessor<boolean> | null;
	viewportFraction?: Accessor<number> | null;
	mode?: Accessor<CarouselMode> | null;
	parallaxScrollingScale?: Accessor<number> | null;
	onSnapToItem?: ((index: number) => void) | null;
	onScrollStart?: (() => void) | null;
	onScrollEnd?: ((index: number) => void) | null;
	style?: Accessor<Style> | null;
}): NeonNode {
	const { onSnapToItem, onScrollStart, onScrollEnd } = props;
	const data = props.data;
	const loopProp = props.loop;
	const autoProp = props.autoPlay;
	const intervalProp = props.autoPlayInterval;
	const reverseProp = props.autoPlayReverse;
	const verticalProp = props.vertical;
	const modeProp = props.mode;
	const scaleProp = props.parallaxScrollingScale;
	const initialProp = props.defaultIndex;
	const loops = (): boolean => loopProp === null || loopProp();
	const autoPlays = (): boolean => autoProp !== null && autoProp();
	const interval = (): number => intervalProp === null ? AUTO_PLAY_INTERVAL : intervalProp();
	const reverse = (): boolean => reverseProp !== null && reverseProp();
	const controller = new PageController(initialProp === null ? 0 : initialProp());
	const userRef = props.ref;
	if (userRef !== null) { userRef(controller); }

	const timer = new TimerHandle();
	let snapped: number = untrack<number>((): number => controller.selectedPage());
	let held = false;
	const cancel = (): void => { timer.cancel(); };
	onCleanup(cancel);
	const advance = (): void => {
		const n = untrack<T[]>(data).length as int32;
		if (n <= 1 || held) { return; }
		const current = untrack<number>((): number => controller.selectedPage());
		const next = current + (untrack<boolean>(reverse) ? -1 : 1);
		if (!untrack<boolean>(loops) && (next < 0 || next >= (n as number))) { return; }
		controller.setPage(next);
	};
	const schedule = (): void => {
		cancel();
		if (!untrack<boolean>(autoPlays) || held) { return; }
		timer.start(advance, untrack<number>(interval));
	};
	createRenderEffect<boolean>(
		(prev: boolean | null): boolean => autoPlays(),
		(playing: boolean, prev: boolean | null): Cleanup | null => {
			if (playing) { schedule(); } else { cancel(); }
			return null;
		},
	);

	const stateChanged = (state: PageScrollState): void => {
		if (state === "dragging") {
			held = true;
			cancel();
			if (onScrollStart !== null) { onScrollStart(); }
			return;
		}
		if (state === "idle") {
			held = false;
			const index = untrack<number>((): number => controller.selectedPage());
			if (index !== snapped) {
				snapped = index;
				if (onSnapToItem !== null) { onSnapToItem(index); }
			}
			if (onScrollEnd !== null) { onScrollEnd(index); }
			schedule();
		}
	};
	const pageStyle = modeProp === null ? null : (delta: number): Style => {
		if (modeProp() !== "parallax") { return {}; }
		const scale = parallaxScale(delta, scaleProp === null ? PARALLAX_SCALE : scaleProp());
		return { transform: `scale(${scale})`, opacity: 0.6 + 0.4 * scale };
	};
	return PageView<T>({
		data,
		renderItem: props.renderItem,
		controller,
		orientation: verticalProp === null ? null : accessor((): PageOrientation => verticalProp() ? "vertical" : "horizontal"),
		scrollEnabled: props.enabled,
		viewportFraction: props.viewportFraction,
		loop: accessor(loops),
		pageStyle,
		onPageScrollStateChanged: stateChanged,
		style: props.style,
	});
}
