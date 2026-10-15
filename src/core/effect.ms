import { Computation, Dispose, EFFECT_RENDER, EFFECT_USER, RUN_UNCHANGED } from "./types";
import { createComputed, startEffect, queueEffect, disposeNode, onServer } from "./runtime";
import { untrack } from "./signal";

function noop(): void {}

function effectRun(fn: () => void): (self: Computation, create: boolean) => int32 {
	return (self: Computation, create: boolean): int32 => {
		fn();
		return RUN_UNCHANGED;
	};
}

export function createEffect(fn: () => void): Dispose {
	if (onServer()) { return noop; }
	const node = createComputed(effectRun(fn), EFFECT_USER, true, false, null);
	queueEffect(node);
	return () => { disposeNode(node); };
}

export function onMount(fn: () => void): void {
	createEffect((): void => { untrack(fn); });
}

export function createRenderEffect(fn: () => void): Dispose {
	const node = createComputed(effectRun(fn), EFFECT_RENDER, true, false, null);
	startEffect(node);
	return () => { disposeNode(node); };
}

export function createBindingEffect(fn: () => void): Dispose {
	const node = createComputed(effectRun(fn), EFFECT_RENDER, true, true, null);
	startEffect(node);
	return () => { disposeNode(node); };
}
