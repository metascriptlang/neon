import { Host, HostNode, MeasureRect, MeasureError } from "./hostTypes";

export { MeasureRect, MeasureError } from "./hostTypes";

export interface DOMRect {
	x: number;
	y: number;
	width: number;
	height: number;
	top: number;
	right: number;
	bottom: number;
	left: number;
}

const NO_RECT: MeasureRect = { x: 0, y: 0, width: 0, height: 0 };

function warnInDebug(message: string): void {
	when (debug) { console.warn(message); }
}

export class ElementHandle {
	node: HostNode;
	private elementHost: Host;
	private elementMounted: () => boolean;

	constructor(host: Host, node: HostNode, mounted: () => boolean) {
		this.elementHost = host;
		this.node = node;
		this.elementMounted = mounted;
	}

	accessibilityFocus(): void {
		if (!this.elementMounted()) {
			warnInDebug("Element.accessibilityFocus was called after unmount, so it does nothing");
			return;
		}
		const focus = this.elementHost.accessibilityFocus;
		if (focus === null) {
			warnInDebug("Element.accessibilityFocus needs a host with the accessibilityFocus capability, and this host has none, so it does nothing");
			return;
		}
		(focus as (node: HostNode) => void)(this.node);
	}

	measure(callback: (x: number, y: number, width: number, height: number, pageX: number, pageY: number) => void): void {
		const page = this.inWindow("Element.measure");
		if (page === null) {
			callback(0, 0, 0, 0, 0, 0);
			return;
		}
		const frame = page as MeasureRect;
		const parent = this.elementHost.parentOf(this.node);
		if (parent === null) {
			callback(frame.x, frame.y, frame.width, frame.height, frame.x, frame.y);
			return;
		}
		const local = this.layoutIn(parent as HostNode);
		if (!local.ok) {
			warnInDebug(`Element.measure could not read the layout in the parent (${local.error.toString()}), so it answers zeros`);
			callback(0, 0, 0, 0, 0, 0);
			return;
		}
		callback(local.value.x, local.value.y, frame.width, frame.height, frame.x, frame.y);
	}

	measureInWindow(callback: (x: number, y: number, width: number, height: number) => void): void {
		const page = this.inWindow("Element.measureInWindow");
		const r = page === null ? NO_RECT : page as MeasureRect;
		callback(r.x, r.y, r.width, r.height);
	}

	measureLayout(relativeTo: ElementHandle, onSuccess: (left: number, top: number, width: number, height: number) => void, onFail: (() => void) | null = null): void {
		let result: Result<MeasureRect, MeasureError> = Result.err(MeasureError.NotMounted);
		if (this.elementMounted() && relativeTo.elementMounted()) {
			result = this.elementHost === relativeTo.elementHost ? this.layoutIn(relativeTo.node) : Result.err(MeasureError.NotAncestor);
		}
		if (result.ok) {
			onSuccess(result.value.x, result.value.y, result.value.width, result.value.height);
		} else if (onFail !== null) {
			(onFail as () => void)();
		} else {
			warnInDebug(`Element.measureLayout failed (${result.error.toString()}) and was given no onFail, so it does nothing`);
		}
	}

	getBoundingClientRect(): DOMRect {
		const page = this.inWindow("Element.getBoundingClientRect");
		const r = page === null ? NO_RECT : page as MeasureRect;
		return { x: r.x, y: r.y, width: r.width, height: r.height, top: r.y, right: r.x + r.width, bottom: r.y + r.height, left: r.x };
	}

	private inWindow(call: string): MeasureRect | null {
		if (!this.elementMounted()) {
			warnInDebug(`${call} was called after unmount, so it answers zeros`);
			return null;
		}
		const measure = this.elementHost.measureInWindow;
		if (measure === null) {
			warnInDebug(`${call} needs a host that measures, and this host has none, so it answers zeros`);
			return null;
		}
		const result = (measure as (node: HostNode) => Result<MeasureRect, MeasureError>)(this.node);
		if (!result.ok) {
			warnInDebug(`${call} failed (${result.error.toString()}), so it answers zeros`);
			return null;
		}
		return result.value;
	}

	private layoutIn(ancestor: HostNode): Result<MeasureRect, MeasureError> {
		const measure = this.elementHost.measureLayout;
		if (measure === null) { return Result.err(MeasureError.Unsupported); }
		return (measure as (node: HostNode, ancestor: HostNode) => Result<MeasureRect, MeasureError>)(this.node, ancestor);
	}
}
