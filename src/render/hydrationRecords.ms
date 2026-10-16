import { hydrating } from "./claim";

const values = new Map<string, string>();
const errors = new Map<string, string>();

when (js) {
	extern function jsHas(table: cstring, id: cstring): boolean from
		"((t, i) => { const h = globalThis._$HY; return h !== undefined && h[t] !== undefined && Object.hasOwn(h[t], i); })(#, #)";
	extern function jsRead(table: cstring, id: cstring): cstring from
		"((t, i) => { const v = globalThis._$HY[t][i]; delete globalThis._$HY[t][i]; return v; })(#, #)";
	extern function jsWrite(table: cstring, id: cstring, value: cstring): void from
		"((t, i, v) => { const h = (globalThis._$HY ??= { r: {}, e: {} }); h[t] ??= {}; h[t][i] = v; })(#, #, #)";
	extern function jsClear(): void from "(delete globalThis._$$HY)";
}

function has(table: string, id: string): boolean {
	if (!hydrating()) { return false; }
	when (js) {
		return jsHas(table, id);
	} else {
		return (table === "r" ? values : errors).has(id);
	}
}

function take(table: string, id: string): string {
	if (!has(table, id)) {
		throw new Error("hydrate: the page has no " + (table === "r" ? "record" : "error record") + " for " + id + " to read");
	}
	when (js) {
		return jsRead(table, id);
	} else {
		const map = table === "r" ? values : errors;
		const text = map.get(id) as string;
		map.delete(id);
		return text;
	}
}

export function hasRecord(id: string): boolean {
	return has("r", id);
}

export function hasError(id: string): boolean {
	return has("e", id);
}

export function takeRecord<T>(id: string): T {
	const decoded = JSON.parse<T>(take("r", id));
	if (!decoded.ok) { throw new Error("hydrate: the record for " + id + " does not decode"); }
	return decoded.value;
}

export function takeError(id: string): string {
	return take("e", id);
}

export function putRecord(id: string, json: string): void {
	when (js) {
		jsWrite("r", id, json);
	} else {
		values.set(id, json);
	}
}

export function putError(id: string, message: string): void {
	when (js) {
		jsWrite("e", id, message);
	} else {
		errors.set(id, message);
	}
}

export function clearRecords(): void {
	when (js) {
		jsClear();
	} else {
		values.clear();
		errors.clear();
	}
}

function hex4(code: int32): string {
	return ("0000" + code.toString(16)).slice(-4);
}

export function scriptLiteral(text: string): string {
	let out = "";
	let last = 0;
	for (let i = 0; i < text.length; i += 1) {
		const c = text.charCodeAt(i);
		if (c >= 32 && c !== 34 && c !== 60 && c !== 92 && c !== 0x2028 && c !== 0x2029) { continue; }
		const e = c === 34 ? "\\\"" : c === 92 ? "\\\\" : "\\u" + hex4(c);
		out = out + text.slice(last, i) + e;
		last = i + 1;
	}
	return last === 0 ? text : out + text.slice(last);
}
