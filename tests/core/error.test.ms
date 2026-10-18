import { createSignal, Accessor } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { createErrorBoundary } from "../../src/core/boundary";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";

test "a throw with no handler still escapes" {
	const [a, setA] = createSignal(0);
	createRenderEffect<int32>(
		(p: int32 | null): int32 => { if (a() === 1) { throw new Error("loud"); } return a(); },
		(v: int32, p: int32 | null): Cleanup | null => null,
	);
	let escaped = "";
	try { setA(1); flush(); } catch (e) { escaped = e.message; }
	assert escaped === "loud", "an unhandled throw is never swallowed: [" + escaped + "]";
	resetErrorHalt();
}

test "an effect-phase throw with no handler still escapes" {
	const [a, setA] = createSignal(0);
	createRenderEffect<int32>(
		(p: int32 | null): int32 => a(),
		(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("loud apply"); } return null; },
	);
	let escaped = "";
	try { setA(1); flush(); } catch (e) { escaped = e.message; }
	assert escaped === "loud apply", "an unhandled throw is never swallowed: [" + escaped + "]";
	resetErrorHalt();
}

// createErrorBoundary.test.ts:41, a thrown value that is not an Error reaches the fallback as an Error carrying it
test "a thrown string reaches the fallback as an Error carrying it" {
	let seen: Error | null = null;
	createRoot((dispose) => {
		const b = createErrorBoundary<string>(
			(): string => { throw "bare 7"; },
			(e: Accessor<Error>, reset: () => void): string => { seen = e(); return "error"; },
		);
		createRenderEffect<string>((p: string | null): string => b(), (v: string, p: string | null): Cleanup | null => null);
		return 0;
	});
	flush();
	assert seen !== null && (seen as Error) instanceof Error, "the string arrives boxed in an Error";
	assert (seen as Error).message === "bare 7", "with the string as its message: [" + (seen as Error).message + "]";
}
