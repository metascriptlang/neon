import { MeasureError } from "../../render/hostTypes";

export const NO_NODE: int32 = -1;
export const NO_HANDLER: int32 = -1;
export const REGION: int32 = 0;
export const REGION_END: int32 = 1;

const INDEX_BITS: int32 = 20;
const INDEX_MASK: int32 = 1048575;
export const GENERATIONS: int32 = 1024;

export const CAN_PARAGRAPH: int32 = 1;
export const CAN_FOCUS: int32 = 2;
export const CAN_SCROLL_TO: int32 = 4;
export const CAN_MEASURE_TEXT: int32 = 8;
export const CAN_MEASURE_IN_WINDOW: int32 = 16;
export const CAN_MEASURE_LAYOUT: int32 = 32;

export const MEASURE_ERRORS: MeasureError[] = [
	MeasureError.NotMounted,
	MeasureError.NotLaidOut,
	MeasureError.NotAncestor,
	MeasureError.Unsupported,
];

export function can(capabilities: int32, capability: int32): boolean {
	return (capabilities & capability) !== 0;
}

export function handleAt(index: int32, generation: int32): int32 {
	return (generation << INDEX_BITS) | index;
}

export function handleIndex(handle: int32): int32 {
	return handle & INDEX_MASK;
}

export function handleGeneration(handle: int32): int32 {
	return handle >> INDEX_BITS;
}
