import { Accessor } from "../core/signal";
import { createAsyncMemo as coreAsyncMemo, MemoOptions } from "../core/memo";
import { hasRecord, hasError, readRecord, readError } from "./hydrationRecords";
import { traceRun } from "./traceRun";

// Parked on ~/metascript/.inbox/compiler/2026-10-15-json-decode-refuses-arrays-of-structs-and-plain-values.md: `JSON.parse<T>` refuses an atom T, so only a struct or interface value adopts a record.
export function createAsyncMemo<T>(compute: (prev: T | null) => Promise<T>, options?: MemoOptions<T>): Accessor<T> {
	return coreAsyncMemo<T>(compute, options, {
		has: (id: string): boolean => hasRecord(id) || hasError(id),
		read: (id: string, trace: () => void): T => {
			traceRun<void>(trace);
			if (hasError(id)) { throw new Error(readError(id)); }
			return readRecord<T>(id);
		},
	});
}
