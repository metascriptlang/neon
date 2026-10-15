import { Host, HostNode, MeasureRect, MeasureError } from "./hostTypes";
import { requestFrame } from "../animation/frame";

export { MeasureRect, MeasureError } from "./hostTypes";
export type ElementRef = (handle: ElementHandle) => void;
export type MeasureCallback = (bounds: MeasureRect) => void;
export type MeasureFailure = (error: MeasureError) => void;

function deliver(result: Result<MeasureRect, MeasureError>, success: MeasureCallback, failure: MeasureFailure | null): void {
	if (result.ok) {
		success(result.value);
	} else if (failure !== null) {
		(failure as MeasureFailure)(result.error);
	} else {
		throw "Element measurement failed: " + result.error.toString();
	}
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

	measureInWindow(success: MeasureCallback, failure: MeasureFailure | null = null): void {
		if (!this.elementMounted()) { throw "Element.measureInWindow was called after unmount"; }
		requestFrame((time: number): void => {
			if (!this.elementMounted()) { return; }
			const measure = this.elementHost.measureInWindow;
			if (measure === null) {
				deliver(Result.err(MeasureError.Unsupported), success, failure);
			} else {
				const result = (measure as (node: HostNode) => Result<MeasureRect, MeasureError>)(this.node);
				if (!this.elementMounted()) { return; }
				deliver(result, success, failure);
			}
		});
	}

	measureLayout(ancestor: ElementHandle, success: MeasureCallback, failure: MeasureFailure | null = null): void {
		if (!this.elementMounted() || !ancestor.elementMounted()) { throw "Element.measureLayout was called after unmount"; }
		if (this.elementHost !== ancestor.elementHost) { throw "Element.measureLayout requires handles from the same host"; }
		requestFrame((time: number): void => {
			if (!this.elementMounted() || !ancestor.elementMounted()) { return; }
			const measure = this.elementHost.measureLayout;
			if (measure === null) {
				deliver(Result.err(MeasureError.Unsupported), success, failure);
			} else {
				const result = (measure as (node: HostNode, parent: HostNode) => Result<MeasureRect, MeasureError>)(this.node, ancestor.node);
				if (!this.elementMounted() || !ancestor.elementMounted()) { return; }
				deliver(result, success, failure);
			}
		});
	}
}
