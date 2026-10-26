import { StorageServices, installStorageServices } from "../../api/storageServices";
import { ensureDir, exists, readFile, rename, writeFile } from "std/fs";
import { homeDir } from "std/os";

const MANIFEST = "manifest.json";

function failure(action: string, path: string, message: string): Error {
	return new Error(`AsyncStorage: cannot ${action} ${path}: ${message}`);
}

export function createIonStorage(directory: string): StorageServices {
	const manifest = directory + "/" + MANIFEST;
	let keys: string[] = [];
	let values: string[] = [];
	let loaded = false;

	function load(): void {
		if (loaded) { return; }
		if (exists(manifest)) {
			const read = readFile(manifest);
			if (!read.ok) { throw failure("read", manifest, read.error.message); }
			const parsed = JSON.parseValue(read.value);
			if (!parsed.ok) { throw failure("parse", manifest, "not a JSON object"); }
			const root: JsonValue = parsed.value;
			if (root.kind !== JsonKind.Object) { throw failure("parse", manifest, "not a JSON object"); }
			for (let i = 0; i < root.keys.length; i += 1) {
				const value = root.values[i];
				if (value.kind !== JsonKind.String) { throw failure("parse", manifest, "the value of " + root.keys[i] + " is not a string"); }
				keys.push(root.keys[i]);
				values.push(value.asString());
			}
		}
		loaded = true;
	}

	function save(): void {
		const made = ensureDir(directory);
		if (!made.ok) { throw failure("create", directory, made.error.message); }
		const json: JsonValue[] = [];
		for (const value of values) { json.push(jsonString(value)); }
		const temp = manifest + ".tmp";
		const written = writeFile(temp, stringify(jsonObject(keys, json)));
		if (!written.ok) { throw failure("write", temp, written.error.message); }
		const moved = rename(temp, manifest);
		if (!moved.ok) { throw failure("replace", manifest, moved.error.message); }
	}

	// A failed save leaves memory ahead of disk, so the next call reloads from the manifest.
	function persist(): void {
		try {
			save();
		} catch (e) {
			loaded = false;
			keys = [];
			values = [];
			throw e;
		}
	}

	return {
		storageGet: (key: string): string | null => {
			load();
			const at = keys.indexOf(key);
			return at < 0 ? null : values[at];
		},
		storageSet: (key: string, value: string): void => {
			load();
			const at = keys.indexOf(key);
			if (at < 0) {
				keys.push(key);
				values.push(value);
			} else {
				values[at] = value;
			}
			persist();
		},
		storageRemove: (key: string): void => {
			load();
			const at = keys.indexOf(key);
			if (at < 0) { return; }
			keys.splice(at, 1);
			values.splice(at, 1);
			persist();
		},
		storageClear: (): void => {
			load();
			keys = [];
			values = [];
			persist();
		},
		storageKeys: (): string[] => {
			load();
			return keys.slice(0, keys.length);
		},
	};
}

let appName = "";

function appDataDirectory(): string {
	if (appName === "") { throw new Error("AsyncStorage: the app name is not set; the host names it before the first call"); }
	when (windows) {
		return homeDir() + "/AppData/Local/" + appName + "/AsyncStorage";
	} else {
		return homeDir() + "/Library/Application Support/" + appName + "/AsyncStorage";
	}
}

export function useIonStorage(name: string): void {
	appName = name;
	installStorageServices(createIonStorage(appDataDirectory()));
}
