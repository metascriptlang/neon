when (js) {
	extern function runUnderMock<T>(run: () => T): void from
		"(run => { class Mock { catch() { return new Mock(); } then() { return new Mock(); } finally() { return new Mock(); } } for (const k of ['all', 'allSettled', 'any', 'race', 'reject', 'resolve', 'try']) Mock[k] = () => new Mock(); Mock.withResolvers = () => ({ promise: new Mock(), resolve() {}, reject() {} }); const ogFetch = globalThis.fetch; const ogPromise = globalThis.Promise; try { globalThis.fetch = () => new Mock(); globalThis.Promise = Mock; const result = run(); if (result && typeof result.next === 'function' && typeof result[Symbol.asyncIterator] === 'function') { const it = result[Symbol.asyncIterator](); if (it === result) it.next(); } if (result && typeof result.then === 'function') result.then(undefined, () => {}); } finally { globalThis.fetch = ogFetch; globalThis.Promise = ogPromise; } })(#)";
}

export function traceRun<T>(run: () => T): void {
	when (js) {
		runUnderMock<T>(run);
	} else {
		run();
	}
}
