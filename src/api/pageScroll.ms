when (js) {
	import { Accessor, accessor, batch, createSignal } from "../core/signal";

	export interface ScrollPosition {
		x: number;
		y: number;
	}

	const [offsetX, setOffsetX] = createSignal<number>(0);
	const [offsetY, setOffsetY] = createSignal<number>(0);
	const [rangeX, setRangeX] = createSignal<number>(0);
	const [rangeY, setRangeY] = createSignal<number>(0);

	export function useWindowScrollPosition(): Accessor<ScrollPosition> {
		return accessor((): ScrollPosition => ({ x: offsetX(), y: offsetY() }));
	}

	export function useWindowScrollRange(): Accessor<ScrollPosition> {
		return accessor((): ScrollPosition => ({ x: rangeX(), y: rangeY() }));
	}

	export function publishPageScroll(x: number, y: number, maxX: number, maxY: number): void {
		batch((): void => {
			if (offsetX() !== x) { setOffsetX(x); }
			if (offsetY() !== y) { setOffsetY(y); }
			if (rangeX() !== maxX) { setRangeX(maxX); }
			if (rangeY() !== maxY) { setRangeY(maxY); }
		});
	}
}
