import { SettingsServices, installedSettingsServices, listenSettings } from "./settingsServices";

when (ios) {
	import "../platform/native/settings";
}

// Source: react-native 693e9628e8c, Libraries/Settings/Settings.ios.js:21-80 and RCTSettingsManager.mm:64-110;
// off iOS the calls warn and answer null or -1 as SettingsFallback.js:13-31 does.
interface Watch {
	keys: string[];
	seen: (string | null)[];
	callback: (() => void) | null;
}

const watches: Watch[] = [];

function unsupported(): void {
	console.warn("Settings is not yet supported on this platform.");
}

function read(services: SettingsServices, key: string): string | null {
	return services.settingsGet(key);
}

function onSettingsChanged(): void {
	const services = installedSettingsServices();
	if (services === null) { return; }
	for (const watch of watches.slice(0, watches.length)) {
		for (let i = 0; i < watch.keys.length; i += 1) {
			const now = read(services, watch.keys[i]);
			if (now === watch.seen[i]) { continue; }
			watch.seen[i] = now;
			const callback = watch.callback;
			if (callback !== null) { callback(); }
		}
	}
}

listenSettings(onSettingsChanged);

export class Settings {
	static get(key: string): JsonValue | null {
		const services = installedSettingsServices();
		if (services === null) {
			unsupported();
			return null;
		}
		const text = read(services, key);
		if (text === null) { return null; }
		const parsed = JSON.parseValue(text);
		if (!parsed.ok) { throw new Error("Settings.get: the stored value of " + key + " is not JSON: " + text); }
		return parsed.value;
	}

	// A null value removes the key, as RCTSettingsManager.mm:86-91 does. Writes made here never fire watchKeys (mm:84-95).
	static set<T>(settings: T): void {
		const services = installedSettingsServices();
		if (services === null) {
			unsupported();
			return;
		}
		const text = JSON.stringify(settings);
		const written = JSON.parseValue(text);
		if (!written.ok) { throw new Error("Settings.set: not JSON: " + text); }
		const value = written.value;
		if (value.kind !== JsonKind.Object) { throw new Error("Settings.set: the settings must be an object, got " + text); }
		services.settingsSet(text);
		for (const watch of watches) {
			for (let i = 0; i < watch.keys.length; i += 1) {
				if (value.keys.indexOf(watch.keys[i]) >= 0) { watch.seen[i] = read(services, watch.keys[i]); }
			}
		}
	}

	static watchKeys(keys: string | string[], callback: () => void): number {
		const services = installedSettingsServices();
		if (services === null) {
			unsupported();
			return -1;
		}
		const list: string[] = typeof keys === "string" ? [keys] : keys;
		const seen: (string | null)[] = [];
		for (const key of list) { seen.push(read(services, key)); }
		services.watchSettings();
		const id = watches.length;
		watches.push({ keys: list, seen, callback });
		return id;
	}

	static clearWatch(watchId: number): void {
		if (installedSettingsServices() === null) {
			unsupported();
			return;
		}
		if (watchId >= 0 && watchId < watches.length) { watches[watchId] = { keys: [], seen: [], callback: null }; }
	}
}
