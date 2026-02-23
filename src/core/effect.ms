// Effect - Side Effect Primitive
// Automatically tracks signal dependencies and re-runs when they change

import { setEffectContext, getEffectContext } from "./signal";

export function createEffect(fn: () => void): void {
	// Save previous effect context
	const prevEffect = getEffectContext();

	// Create wrapper that can be subscribed to signals
	function effectWrapper(): void {
		setEffectContext(effectWrapper);
		fn();
		setEffectContext(prevEffect);
	}

	// Run immediately to establish dependencies
	effectWrapper();
}
