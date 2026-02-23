// Batch - Deferred Updates
// Execute multiple signal updates but only trigger effects once

let batchDepth = 0;
let pendingEffects: Set<() => void> = new Set();

export function batch(fn: () => void): void {
	batchDepth++;
	try {
		fn();
	} finally {
		batchDepth--;
		if (batchDepth === 0) {
			flushEffects();
		}
	}
}

export function scheduleBatchEffect(effect: () => void): void {
	if (batchDepth > 0) {
		pendingEffects.add(effect);
	} else {
		effect();
	}
}

function flushEffects(): void {
	const effects = Array.from(pendingEffects);
	pendingEffects.clear();
	effects.forEach(effect => effect());
}
