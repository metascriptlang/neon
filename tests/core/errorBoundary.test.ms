// Pins for createErrorBoundary. Reference: solid-next packages/signals/tests/createErrorBoundary.test.ts @ 84dada77, each test cites its
// line. Left out: the hold and transition tests (:229, :266), which need lanes; "memo in the middle" (:206), which needs the reference's
// flatten of an accessor child; and "holds user effects behind the fallback" (:1098), which needs queued runs held behind a fallback.
import { createSignal, Accessor } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect, EffectBundle } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { createErrorBoundary } from "../../src/core/boundary";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";

function watch<T>(read: Accessor<T>): void {
	createRenderEffect<T>((p: T | null): T => read(), (v: T, p: T | null): Cleanup | null => null);
}

// createErrorBoundary.test.ts:20
test "an error nobody handles still escapes and halts" {
	const boom = new Error("unhandled");
	let escaped: Error | null = null;
	try {
		createRoot((dispose) => {
			createRenderEffect<int32>((p: int32 | null): int32 => { throw boom; }, (v: int32, p: int32 | null): Cleanup | null => null);
			return 0;
		});
		flush();
	} catch (e) {
		escaped = e;
	}
	assert escaped === boom, "the error reached the caller";
	resetErrorHalt();
}

// createErrorBoundary.test.ts:41
test "an error thrown while the content is made shows the fallback" {
	const boom = new Error("boom");
	const b = createRoot((dispose) => createErrorBoundary<string>(
		(): string => { throw boom; },
		(e: Accessor<Error>, reset: () => void): string => "errored",
	));
	assert b() === "errored", "the fallback shows on creation: " + b();
}

// createErrorBoundary.test.ts:56
test "a fallback that rethrows hands the error to the next boundary" {
	const boom = new Error("boom");
	let seen: Error | null = null;
	const outer = createRoot((dispose) => createErrorBoundary<string>(
		(): string => {
			const inner = createErrorBoundary<string>(
				(): string => { throw boom; },
				(e: Accessor<Error>, reset: () => void): string => { seen = e(); throw e(); },
			);
			watch<string>(inner);
			return "content";
		},
		(e: Accessor<Error>, reset: () => void): string => "errored",
	));
	assert seen === boom, "the inner fallback was given the error";
	assert outer() === "errored", "the outer fallback shows: " + outer();
}

// createErrorBoundary.test.ts:80
test "a fallback is built once for one failure" {
	const boom = new Error("boom");
	const [x, setX] = createSignal<int32>(0);
	let shouldThrow = false;
	let handled = 0;
	createRoot((dispose) => {
		const b = createErrorBoundary<string>(
			(): string => { x(); if (shouldThrow) { throw boom; } return "content"; },
			(e: Accessor<Error>, reset: () => void): string => { handled += 1; return "errored"; },
		);
		watch<string>(b);
		return 0;
	});
	setX(1);
	flush();
	assert handled === 0, "no failure yet";
	shouldThrow = true;
	setX(2);
	flush();
	assert handled === 1, "one failure, one fallback: " + handled.toString();
}

// createErrorBoundary.test.ts:107
test "an error reaches the boundary that contains it, not one beside it" {
	const boom = new Error("boom");
	const [x, setX] = createSignal<int32>(0);
	let shouldThrow = false;
	let rootHandled = 0;
	let innerHandled = 0;
	createRoot((dispose) => {
		const b = createErrorBoundary<string>(
			(): string => {
				createRenderEffect<int32>(
					(p: int32 | null): int32 => { x(); if (shouldThrow) { throw boom; } return 0; },
					(v: int32, p: int32 | null): Cleanup | null => null,
				);
				const b2 = createErrorBoundary<string>(
					(): string => "quiet",
					(e: Accessor<Error>, reset: () => void): string => { innerHandled += 1; return "inner"; },
				);
				watch<string>(b2);
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { rootHandled += 1; return "errored"; },
		);
		watch<string>(b);
		return 0;
	});
	assert rootHandled === 0, "nothing failed yet";
	shouldThrow = true;
	setX(1);
	flush();
	assert rootHandled === 1, "the containing boundary caught it: " + rootHandled.toString();
	assert innerHandled === 0, "the boundary beside it did not";
}

// createErrorBoundary.test.ts:148
test "an error no boundary handles escapes through every fallback that rethrows" {
	const boom = new Error("boom");
	let handled = 0;
	let escaped: Error | null = null;
	createRoot((dispose) => {
		try {
			const outer = createErrorBoundary<string>(
				(): string => {
					const inner = createErrorBoundary<string>(
						(): string => { throw boom; },
						(e: Accessor<Error>, reset: () => void): string => { handled += 1; throw e(); },
					);
					return inner();
				},
				(e: Accessor<Error>, reset: () => void): string => { handled += 1; throw e(); },
			);
			outer();
		} catch (e) {
			escaped = e;
		}
		return 0;
	});
	assert escaped === boom, "the error reached the caller";
	assert handled === 2, "both fallbacks saw it: " + handled.toString();
	resetErrorHalt();
}

// createErrorBoundary.test.ts:173
test "a boundary that fails later hands the fallback the error it made" {
	const boom = new Error("boom");
	const [x, setX] = createSignal<int32>(0);
	let rootSaw: Error | null = null;
	let innerSaw: Error | null = null;
	createRoot((dispose) => {
		const b = createErrorBoundary<string>(
			(): string => {
				if (x() > 0) { throw boom; }
				createErrorBoundary<string>(
					(): string => { throw boom; },
					(e: Accessor<Error>, reset: () => void): string => { innerSaw = e(); return "inner"; },
				);
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { rootSaw = e(); return "errored"; },
		);
		watch<string>(b);
		return 0;
	});
	assert rootSaw === null, "nothing failed in the outer one yet";
	assert innerSaw === boom, "the inner fallback shows on creation";
	setX(1);
	flush();
	assert rootSaw === boom, "the outer fallback was given the error";
}

// createErrorBoundary.test.ts:309
test "a throw in a render effect's callback shows the fallback" {
	const boom = new Error("render callback");
	let seen: Error | null = null;
	createRoot((dispose) => {
		const b = createErrorBoundary<string>(
			(): string => {
				createRenderEffect<string>((p: string | null): string => "value", (v: string, p: string | null): Cleanup | null => { throw boom; });
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { seen = e(); return "errored"; },
		);
		watch<string>(b);
		return 0;
	});
	flush();
	assert seen === boom, "the fallback was given the callback's error";
}

// createErrorBoundary.test.ts:337
test "a throw in a user effect's callback shows the fallback" {
	const boom = new Error("user callback");
	let seen: Error | null = null;
	let result = "";
	createRoot((dispose) => {
		const b = createErrorBoundary<string>(
			(): string => {
				createEffect<string>((p: string | null): string => "value", (v: string, p: string | null): Cleanup | null => { throw boom; });
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { seen = e(); return "errored"; },
		);
		createRenderEffect<string>((p: string | null): string => { result = b(); return result; }, (v: string, p: string | null): Cleanup | null => null);
		return 0;
	});
	flush();
	assert seen === boom, "the fallback was given the callback's error";
	assert result === "errored", "and it shows: " + result;
}

// createErrorBoundary.test.ts:370
test "a throw in an effect's cleanup shows the fallback" {
	const [n, setN] = createSignal<int32>(0);
	let seen = "";
	let result = "";
	createRoot((dispose) => {
		const b = createErrorBoundary<string>(
			(): string => {
				createEffect<int32>((p: int32 | null): int32 => n(), (v: int32, p: int32 | null): Cleanup | null => {
					return (): void => { if (v === 0) { throw new Error("cleanup boom"); } };
				});
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { seen = e().message; return "errored"; },
		);
		createRenderEffect<string>((p: string | null): string => { result = b(); return result; }, (v: string, p: string | null): Cleanup | null => null);
		return 0;
	});
	flush();
	setN(1);
	flush();
	assert seen === "cleanup boom", "the fallback was given the cleanup's error: [" + seen + "]";
	assert result === "errored", "and it shows: " + result;
}

// createErrorBoundary.test.ts:404
test "a throw in a callback goes to the boundary even when the effect has an error arm" {
	const boom = new Error("bundle callback");
	let seen: Error | null = null;
	let armed = 0;
	let result = "";
	const bundle: EffectBundle<string> = {
		effect: (v: string, p: string | null): Cleanup | null => { throw boom; },
		error: (err: Error, cleanup: Cleanup): void => { armed += 1; },
	};
	createRoot((dispose) => {
		const b = createErrorBoundary<string>(
			(): string => {
				createEffect<string>((p: string | null): string => "value", bundle);
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { seen = e(); return "errored"; },
		);
		createRenderEffect<string>((p: string | null): string => { result = b(); return result; }, (v: string, p: string | null): Cleanup | null => null);
		return 0;
	});
	flush();
	assert seen === boom, "the fallback was given the callback's error";
	assert armed === 0, "the error arm is for compute errors, not callback throws";
	assert result === "errored", "and it shows: " + result;
}

// createErrorBoundary.test.ts:438
test "reset recovers from a callback error" {
	const boom = new Error("callback");
	let shouldThrow = true;
	let result = "";
	let resetFn: (() => void) | null = null;
	createRoot((dispose) => {
		const b = createErrorBoundary<string>(
			(): string => {
				createRenderEffect<string>((p: string | null): string => "value", (v: string, p: string | null): Cleanup | null => { if (shouldThrow) { throw boom; } return null; });
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { resetFn = reset; return "errored"; },
		);
		createRenderEffect<string>((p: string | null): string => { result = b(); return result; }, (v: string, p: string | null): Cleanup | null => null);
		return 0;
	});
	flush();
	assert result === "errored", "failed: " + result;
	assert resetFn !== null, "the fallback was given a reset";
	shouldThrow = false;
	(resetFn as () => void)();
	flush();
	assert result === "content", "recovered: " + result;
}

// createErrorBoundary.test.ts:476
test "a callback error with no boundary escapes" {
	const boom = new Error("uncaught");
	let escaped: Error | null = null;
	try {
		createRoot((dispose) => {
			createRenderEffect<string>((p: string | null): string => "value", (v: string, p: string | null): Cleanup | null => { throw boom; });
			return 0;
		});
		flush();
	} catch (e) {
		escaped = e;
	}
	assert escaped === boom, "the error reached the caller";
	resetErrorHalt();
}

// createErrorBoundary.test.ts:540
test "reset recovers a memo whose input changed" {
	const [id, setId] = createSignal<string>("bad");
	let result = "";
	let resetFn: (() => void) | null = null;
	createRoot((dispose) => {
		const data = createMemo<string>((p: string | null): string => {
			const now = id();
			if (now !== "1") { throw new Error("Item " + now + " not found"); }
			return "ok";
		});
		const b = createErrorBoundary<string>(
			(): string => data(),
			(e: Accessor<Error>, reset: () => void): string => { resetFn = reset; return "error"; },
		);
		createRenderEffect<string>((p: string | null): string => { result = b(); return result; }, (v: string, p: string | null): Cleanup | null => null);
		return 0;
	});
	flush();
	assert result === "error", "failed: " + result;
	setId("1");
	(resetFn as () => void)();
	flush();
	assert result === "ok", "recovered: " + result;
}

// createErrorBoundary.test.ts:1046
test "a second error reaches the fallback through the accessor and does not rebuild it" {
	const [a, setA] = createSignal<int32>(0);
	const [b, setB] = createSignal<int32>(0);
	let fallbackRuns = 0;
	let shown = "";
	createRoot((dispose) => {
		const boundary = createErrorBoundary<string>(
			(): string => {
				createRenderEffect<int32>(
					(p: int32 | null): int32 => { if (a() > 0) { throw new Error("a:" + a().toString()); } return 0; },
					(v: int32, p: int32 | null): Cleanup | null => null,
				);
				createRenderEffect<int32>(
					(p: int32 | null): int32 => { if (b() > 0) { throw new Error("b:" + b().toString()); } return 0; },
					(v: int32, p: int32 | null): Cleanup | null => null,
				);
				return "content";
			},
			(err: Accessor<Error>, reset: () => void): string => {
				fallbackRuns += 1;
				createRenderEffect<string>((p: string | null): string => err().message, (m: string, p: string | null): Cleanup | null => { shown = m; return null; });
				return "fallback";
			},
		);
		watch<string>(boundary);
		return 0;
	});
	flush();
	assert fallbackRuns === 0, "content shows";
	setA(1);
	flush();
	assert fallbackRuns === 1 && shown === "a:1", "first failure: runs=" + fallbackRuns.toString() + " shown=" + shown;
	setB(1);
	flush();
	assert fallbackRuns === 1, "the fallback was not rebuilt: " + fallbackRuns.toString();
	assert shown === "b:1", "the accessor moved to the latest error: " + shown;
}

// createErrorBoundary.test.ts:1098
test "a user effect's run waits behind the error fallback until recovery" {
	const log: string[] = [];
	const [count, setCount] = createSignal<int32>(0);
	const [bad, setBad] = createSignal<boolean>(false);
	let result = "";
	let resetFn: (() => void) | null = null;
	createRoot((dispose) => {
		const boundary = createErrorBoundary<string>(
			(): string => {
				createEffect<int32>((p: int32 | null): int32 => count(), (v: int32, p: int32 | null): Cleanup | null => { log.push("user " + v.toString()); return null; });
				createRenderEffect<int32>((p: int32 | null): int32 => { if (bad()) { throw new Error("boom"); } return 0; }, (v: int32, p: int32 | null): Cleanup | null => null);
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { resetFn = reset; return "fallback"; },
		);
		createRenderEffect<string>((p: string | null): string => boundary(), (v: string, p: string | null): Cleanup | null => { result = v; return null; });
		return 0;
	});
	flush();
	assert result === "content" && log.join(",") === "user 0", "content: " + result + " log=" + log.join(",");
	setBad(true);
	flush();
	assert result === "fallback", "failed: " + result;
	setCount(1);
	flush();
	assert log.join(",") === "user 0", "behind the fallback the run is due, not run: " + log.join(",");
	setBad(false);
	(resetFn as () => void)();
	flush();
	assert result === "content", "recovered: " + result;
	assert log.join(",") === "user 0,user 1", "and the run goes once, with the latest value: " + log.join(",");
}
