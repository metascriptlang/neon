import { JsonValue } from "std/serialize/json";
import { jsonObject, jsonString, jsonNumber, jsonInt } from "std/serialize/json/builder";
import { stringify } from "std/serialize/json/stringify";
import { listeners } from "../render/voidAreaHandle";

when (!js) {
	import { env } from "std/process";
	import { appendFile } from "std/fs";
}

export const DEV_EVENTS_VERSION = 1;

const subscribers = listeners<string>();
let subscribed = 0;
let sinkPath: string | null = null;

function eventFile(): string {
	when (js) {
		return "";
	} else {
		if (sinkPath === null) { sinkPath = env.get("NEON_EVENTS"); }
		return sinkPath as string;
	}
}

export function devEventsWanted(): boolean {
	return subscribed > 0 || eventFile() !== "";
}

export function onDevEvent(fn: (line: string) => void): () => void {
	const off = subscribers.add(fn);
	subscribed += 1;
	let on = true;
	return (): void => {
		if (!on) { return; }
		on = false;
		subscribed -= 1;
		off();
	};
}

export function devEventLine(name: string, keys: string[], values: JsonValue[]): string {
	const k: string[] = ["v", "t", "event"];
	const v: JsonValue[] = [jsonInt(DEV_EVENTS_VERSION as int64), jsonNumber(Date.now()), jsonString(name)];
	for (let i = 0; i < keys.length; i += 1) {
		k.push(keys[i]);
		v.push(values[i]);
	}
	return stringify(jsonObject(k, v), false);
}

export function devEvent(name: string, keys: string[], values: JsonValue[]): void {
	if (keys.length !== values.length) { throw new Error(`devEvent ${name}: ${keys.length} keys for ${values.length} values`); }
	if (!devEventsWanted()) { return; }
	const line = devEventLine(name, keys, values);
	when (!js) {
		const path = eventFile();
		if (path !== "") {
			const written = appendFile(path, line + "\n");
			if (!written.ok) { console.log(`neon devtools: cannot append to NEON_EVENTS ${path}: ${written.error.toString()}`); }
		}
	}
	subscribers.emit(line);
}
