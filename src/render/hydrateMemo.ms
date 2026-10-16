import { Accessor } from "../core/signal";
import { createAsyncMemo as coreAsyncMemo, MemoOptions } from "../core/memo";
import { hasRecord, hasError, readRecord, readError } from "./hydrationRecords";
import { traceRun } from "./traceRun";

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
