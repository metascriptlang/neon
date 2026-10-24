import { Accessor, Signal } from "../core/signal";
import { MemoOptions } from "../core/memo";
import { getOwner, isTracking } from "../core/runtime";
import { onCleanup } from "../core/cleanup";
import { createAsyncMemo } from "../render/hydrateMemo";
import { hasRecord, hasError, readRecord, readError, dropRecord } from "../render/hydrationRecords";

when (server) {
	import { serverContext } from "../core/serverContext";
	import { serverQuery } from "../core/memo";
}

const PRELOAD_TIMEOUT: float64 = 5000;
const CACHE_TIMEOUT: float64 = 180000;
const SWEEP_EVERY: float64 = 300000;

class Answer<R> {
	promise: Promise<R>;

	constructor(promise: Promise<R>) {
		this.promise = promise;
	}
}

class QueryEntry {
	at: float64;
	result: unknown;
	version: Signal<int32> = new Signal<int32>(0);
	readers: int32 = 0;

	constructor(at: float64, result: unknown) {
		this.at = at;
		this.result = result;
	}
}

const cache = new Map<string, QueryEntry>();
let swept: float64 = Date.now();

function sweep(now: float64): void {
	if (now - swept < SWEEP_EVERY) { return; }
	swept = now;
	const stale: string[] = [];
	for (const [key, entry] of cache) {
		if (entry.readers === 0 && now - entry.at > CACHE_TIMEOUT) { stale.push(key); }
	}
	for (const key of stale) { cache.delete(key); }
}

// Parked on ~/metascript/.inbox/compiler/2026-10-24-json-stringify-of-a-tuple-is-refused.md: one `JSON.stringify(args)` in place of these per-arity joins.
export function hashKey(): string {
	return "[]";
}

export function hashKey<A>(a: A): string {
	return "[" + JSON.stringify<A>(a) + "]";
}

export function hashKey<A, B>(a: A, b: B): string {
	return "[" + JSON.stringify<A>(a) + "," + JSON.stringify<B>(b) + "]";
}

// Parked on ~/metascript/.inbox/compiler/2026-10-24-design-a-property-assigned-onto-a-function-value.md: Solid Router's `getUser.key` and `getUser.keyFor(...args)` on the query itself.
export function queryKey(name: string): string {
	return name + hashKey();
}

export function queryKey<A>(name: string, a: A): string {
	return name + hashKey<A>(a);
}

export function queryKey<A, B>(name: string, a: A, b: B): string {
	return name + hashKey<A, B>(a, b);
}

function ownerIdShaped(key: string): boolean {
	for (let i = 0; i < key.length; i += 1) {
		const c = key.charCodeAt(i);
		if ((c < 48 || c > 57) && c !== 45) { return false; }
	}
	return true;
}

function checkedName(name: string): string {
	if (ownerIdShaped(queryKey(name))) { throw new Error("query: the name \"" + name + "\" makes a key shaped like an owner id, which a hydration record of a memo already owns"); }
	return name;
}

async function resolved<R>(value: R): Promise<R> {
	return value;
}

async function rejected<R>(failure: Error): Promise<R> {
	throw failure;
}

function adopted<R>(key: string): Promise<R> {
	const failed = hasError(key);
	const message = failed ? readError(key) : "";
	const value = failed ? null : readRecord<R>(key);
	dropRecord(key);
	return failed ? rejected<R>(new Error(message)) : resolved<R>(value as R);
}

function follow(entry: QueryEntry): void {
	if (!isTracking() || getOwner() === null) { return; }
	entry.readers += 1;
	onCleanup((): void => { entry.readers -= 1; });
	entry.version.get();
}

function cached<R>(key: string, run: () => Promise<R>): Promise<R> {
	when (server) {
		const ctx = serverContext();
		if (ctx !== null) { return serverQuery<R>(ctx, key, run); }
	}
	const now = Date.now();
	const held = cache.get(key);
	if (held !== null && held.at !== 0 && (held.readers > 0 || now - held.at < PRELOAD_TIMEOUT)) {
		follow(held);
		return (held.result as Answer<R>).promise;
	}
	const result = hasRecord(key) || hasError(key) ? adopted<R>(key) : run();
	let entry = held;
	if (entry === null) {
		sweep(now);
		entry = new QueryEntry(now, new Answer<R>(result) as unknown);
		cache.set(key, entry);
	} else {
		entry.at = now;
		entry.result = new Answer<R>(result) as unknown;
	}
	follow(entry);
	return result;
}

// Parked on ~/metascript/.inbox/compiler/2026-10-24-a-generic-rest-parameter-typed-by-a-tuple-type-parameter-is-refused.md: one `query<A extends unknown[], R>` over any arity in place of these overloads.
export function query<R>(fn: () => Promise<R>, name: string): () => Promise<R> {
	checkedName(name);
	return (): Promise<R> => cached<R>(queryKey(name), fn);
}

export function query<A, R>(fn: (a: A) => Promise<R>, name: string): (a: A) => Promise<R> {
	checkedName(name);
	return (a: A): Promise<R> => cached<R>(queryKey<A>(name, a), (): Promise<R> => fn(a));
}

export function query<A, B, R>(fn: (a: A, b: B) => Promise<R>, name: string): (a: A, b: B) => Promise<R> {
	checkedName(name);
	return (a: A, b: B): Promise<R> => cached<R>(queryKey<A, B>(name, a, b), (): Promise<R> => fn(a, b));
}

function matches(key: string, prefixes: string[] | null): boolean {
	if (prefixes === null) { return true; }
	for (const prefix of prefixes) {
		if (prefix !== "" && key.startsWith(prefix)) { return true; }
	}
	return false;
}

function revalidateMatching(prefixes: string[] | null): void {
	const hit: QueryEntry[] = [];
	for (const [key, entry] of cache) {
		if (matches(key, prefixes)) {
			entry.at = 0;
			hit.push(entry);
		}
	}
	for (const entry of hit) { entry.version.set(entry.version.peek() + 1); }
}

export function revalidate(): void {
	revalidateMatching(null);
}

export function revalidate(key: string): void {
	revalidateMatching([key]);
}

export function revalidate(keys: string[]): void {
	revalidateMatching(keys);
}

export function createAsync<T>(fn: () => Promise<T>, options?: MemoOptions<T>): Accessor<T> {
	return createAsyncMemo<T>((prev: T | null): Promise<T> => fn(), options);
}
