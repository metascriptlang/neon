import { appServices } from "./services";

export type KeyValuePair = [string, string | null];
export type StringPair = [string, string];

function readItem(api: string, key: string): string | null {
	return appServices(api).storageGet(key);
}

function parsed(api: string, key: string, text: string): JsonValue {
	const value = JSON.parseValue(text);
	if (!value.ok) { throw new Error(api + ": the value of " + key + " is not JSON: " + text); }
	return value.value;
}

function deepMerge(base: JsonValue, patch: JsonValue): JsonValue {
	if (base.kind !== JsonKind.Object || patch.kind !== JsonKind.Object) { return patch; }
	const keys: string[] = base.keys.slice(0, base.keys.length);
	const values: JsonValue[] = base.values.slice(0, base.values.length);
	for (let i = 0; i < patch.keys.length; i += 1) {
		const at = keys.indexOf(patch.keys[i]);
		if (at < 0) {
			keys.push(patch.keys[i]);
			values.push(patch.values[i]);
		} else {
			values[at] = deepMerge(values[at], patch.values[i]);
		}
	}
	return jsonObject(keys, values);
}

function mergeOne(api: string, key: string, value: string): void {
	const patch = parsed(api, key, value);
	const existing = readItem(api, key);
	const merged = existing === null ? patch : deepMerge(parsed(api, key, existing), patch);
	appServices(api).storageSet(key, stringify(merged));
}

export class AsyncStorage {
	// A throwing call is bound before `return` (compiler card
	// 2026-10-08-async-return-of-a-throwing-call-loses-the-exception-on-c.md).
	static async getItem(key: string): Promise<string | null> {
		const value = readItem("AsyncStorage.getItem", key);
		return value;
	}

	static async setItem(key: string, value: string): Promise<void> {
		appServices("AsyncStorage.setItem").storageSet(key, value);
	}

	static async mergeItem(key: string, value: string): Promise<void> {
		mergeOne("AsyncStorage.mergeItem", key, value);
	}

	static async removeItem(key: string): Promise<void> {
		appServices("AsyncStorage.removeItem").storageRemove(key);
	}

	static async clear(): Promise<void> {
		appServices("AsyncStorage.clear").storageClear();
	}

	static async getAllKeys(): Promise<string[]> {
		const keys = appServices("AsyncStorage.getAllKeys").storageKeys();
		return keys;
	}

	static async multiGet(keys: string[]): Promise<KeyValuePair[]> {
		const pairs: KeyValuePair[] = [];
		for (const key of keys) { pairs.push([key, readItem("AsyncStorage.multiGet", key)]); }
		return pairs;
	}

	static async multiSet(keyValuePairs: StringPair[]): Promise<void> {
		const services = appServices("AsyncStorage.multiSet");
		for (const pair of keyValuePairs) { services.storageSet(pair[0], pair[1]); }
	}

	static async multiMerge(keyValuePairs: StringPair[]): Promise<void> {
		for (const pair of keyValuePairs) { mergeOne("AsyncStorage.multiMerge", pair[0], pair[1]); }
	}

	static async multiRemove(keys: string[]): Promise<void> {
		const services = appServices("AsyncStorage.multiRemove");
		for (const key of keys) { services.storageRemove(key); }
	}

	static flushGetRequests(): void {}
}

// A class, not an object of async arrows: on JS a function holding an async arrow is emitted
// async itself (compiler card 2026-10-07-js-outer-function-made-async-by-nested-async.md).
export class AsyncStorageHook {
	private key: string;

	constructor(key: string) {
		this.key = key;
	}

	async getItem(): Promise<string | null> {
		return await AsyncStorage.getItem(this.key);
	}

	async setItem(value: string): Promise<void> {
		await AsyncStorage.setItem(this.key, value);
	}

	async mergeItem(value: string): Promise<void> {
		await AsyncStorage.mergeItem(this.key, value);
	}

	async removeItem(): Promise<void> {
		await AsyncStorage.removeItem(this.key);
	}
}

export function useAsyncStorage(key: string): AsyncStorageHook {
	return new AsyncStorageHook(key);
}
