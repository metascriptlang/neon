import { INT32_MAX, checkedInt32 } from "./hostCodec";
import { SettingsServices, installedSettingsServices, listenSettings } from "./settingsServices";
import { EventSubscription, Listeners } from "./subscription";

when (ios) {
	import "../platform/native/settings";
}

// Source: react-native 693e9628e8c, Libraries/Settings/Settings.ios.js:21-80 and RCTSettingsManager.mm:64-110;
// off iOS the calls warn and answer null or -1 as SettingsFallback.js:13-31 does.
interface SettingsEvent {
	services: SettingsServices;
	written: string[] | null;
}

const watches = new Listeners<SettingsEvent>();
const subscriptions = new Map<int32, EventSubscription>();
let nextWatch: int32 = 0;

function unsupported(): void {
	console.warn("Settings is not yet supported on this platform.");
}

function read(services: SettingsServices, key: string): string | null {
	return services.settingsGet(key);
}

function onSettingsChanged(): void {
	const services = installedSettingsServices();
	if (services === null) { return; }
	watches.emit({ services, written: null });
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
		watches.emit({ services, written: value.keys });
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
		const id = nextWatch;
		nextWatch += 1;
		subscriptions.set(id, watches.add((event: SettingsEvent): void => {
			for (let i = 0; i < list.length; i += 1) {
				if (event.written !== null) {
					if (event.written.indexOf(list[i]) >= 0) {
						seen[i] = read(event.services, list[i]);
					}
					continue;
				}
				const now = read(event.services, list[i]);
				if (now === seen[i]) { continue; }
				seen[i] = now;
				callback();
			}
		}));
		return id;
	}

	static clearWatch(watchId: number): void {
		if (installedSettingsServices() === null) {
			unsupported();
			return;
		}
		const id = checkedInt32("Settings.clearWatch", "watchId", watchId, 0, INT32_MAX);
		const subscription = subscriptions.get(id);
		if (subscription === null) { return; }
		subscription.remove();
		subscriptions.delete(id);
	}
}
