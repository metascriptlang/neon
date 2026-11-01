import { storageServices } from "./storageServices";

when (js && !server) {
	import "../platform/browser/asyncStorage";
} else when (ios || android) {
	import "../platform/native/asyncStorage";
} else when (macos || windows) {
	import "../platform/ion/storage";
}

export type KeyValuePair = [string, string | null];
export type StringPair = [string, string];

function readItem(api: string, key: string): string | null {
	return storageServices(api).storageGet(key);
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
	storageServices(api).storageSet(key, stringify(merged));
}

export class AsyncStorage {
	// A throwing call is bound before `return` (compiler card
	// 2026-10-08-async-return-of-a-throwing-call-loses-the-exception-on-c.md).
	static async getItem(key: string): Promise<string | null> {
		const value = readItem("AsyncStorage.getItem", key);
		return value;
	}

	static async setItem(key: string, value: string): Promise<void> {
		storageServices("AsyncStorage.setItem").storageSet(key, value);
	}

	static async mergeItem(key: string, value: string): Promise<void> {
		mergeOne("AsyncStorage.mergeItem", key, value);
	}

	static async removeItem(key: string): Promise<void> {
		storageServices("AsyncStorage.removeItem").storageRemove(key);
	}

	static async clear(): Promise<void> {
		storageServices("AsyncStorage.clear").storageClear();
	}

	static async getAllKeys(): Promise<string[]> {
		const keys = storageServices("AsyncStorage.getAllKeys").storageKeys();
		return keys;
	}

	static async multiGet(keys: string[]): Promise<KeyValuePair[]> {
		const pairs: KeyValuePair[] = [];
		for (const key of keys) { pairs.push([key, readItem("AsyncStorage.multiGet", key)]); }
		return pairs;
	}

	static async multiSet(keyValuePairs: StringPair[]): Promise<void> {
		const services = storageServices("AsyncStorage.multiSet");
		for (const pair of keyValuePairs) { services.storageSet(pair[0], pair[1]); }
	}

	static async multiMerge(keyValuePairs: StringPair[]): Promise<void> {
		for (const pair of keyValuePairs) { mergeOne("AsyncStorage.multiMerge", pair[0], pair[1]); }
	}

	static async multiRemove(keys: string[]): Promise<void> {
		const services = storageServices("AsyncStorage.multiRemove");
		for (const key of keys) { services.storageRemove(key); }
	}

	static flushGetRequests(): void {}
}

export interface AsyncStorageHook {
	getItem: () => Promise<string | null>;
	setItem: (value: string) => Promise<void>;
	mergeItem: (value: string) => Promise<void>;
	removeItem: () => Promise<void>;
}

export function useAsyncStorage(key: string): AsyncStorageHook {
	return {
		getItem: async (): Promise<string | null> => await AsyncStorage.getItem(key),
		setItem: async (value: string): Promise<void> => { await AsyncStorage.setItem(key, value); },
		mergeItem: async (value: string): Promise<void> => { await AsyncStorage.mergeItem(key, value); },
		removeItem: async (): Promise<void> => { await AsyncStorage.removeItem(key); },
	};
}
