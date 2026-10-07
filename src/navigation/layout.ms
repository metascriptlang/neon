import { Accessor, Setter, createSignal } from "../core/signal";
import { NeonEvent } from "../render/event";
import { useWindowDimensions } from "../render/environment";

const windowSize = useWindowDimensions();

export class StackLayout {
	width: Accessor<number>;
	height: Accessor<number>;
	writeWidth: Setter<number>;
	writeHeight: Setter<number>;

	constructor() {
		const [width, writeWidth] = createSignal<number>(0);
		const [height, writeHeight] = createSignal<number>(0);
		this.width = width;
		this.height = height;
		this.writeWidth = writeWidth;
		this.writeHeight = writeHeight;
	}

	measure(e: NeonEvent): void {
		if (e.width > 0) { this.writeWidth(e.width); }
		if (e.height > 0) { this.writeHeight(e.height); }
	}

	extentX(): number {
		const own = this.width();
		return own > 0 ? own : windowSize().width;
	}

	extentY(): number {
		const own = this.height();
		return own > 0 ? own : windowSize().height;
	}
}

