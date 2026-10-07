import { niAppCall } from "./app.h";

const FIELD = "\u001f";
const PRESENT = "=";

function call(name: string, arg: string): string {
	const reply: string = niAppCall(name, arg);
	return reply;
}

export function storageGet(key: string): string | null {
	const reply = call("storage.get", key);
	return reply.startsWith(PRESENT) ? reply.substring(1, reply.length) : null;
}

export function storageSet(key: string, value: string): void {
	call("storage.set", key + FIELD + value);
}

export function storageRemove(key: string): void {
	call("storage.remove", key);
}

export function storageClear(): void {
	call("storage.clear", "");
}

export function storageKeys(): string[] {
	const reply = call("storage.keys", "");
	return reply === "" ? [] : reply.split(FIELD);
}
