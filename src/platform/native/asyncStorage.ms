import { StorageServices, installStorageServices } from "../../api/storageServices";
import { FIELD, appCall } from "./appBridge";
import { niStorageCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/storage.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/storage");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		const reply: string = niStorageCommand(name, arg);
		return reply;
	}
} else {
	function command(name: string, arg: string): string {
		return appCall(name, arg);
	}
}

const PRESENT = "=";

function storageGet(key: string): string | null {
	const reply = command("storage.get", key);
	return reply.startsWith(PRESENT) ? reply.substring(1, reply.length) : null;
}

function storageSet(key: string, value: string): void {
	command("storage.set", key + FIELD + value);
}

function storageRemove(key: string): void {
	command("storage.remove", key);
}

function storageClear(): void {
	command("storage.clear", "");
}

function storageKeys(): string[] {
	const reply = command("storage.keys", "");
	return reply === "" ? [] : reply.split(FIELD);
}

export const nativeStorageServices: StorageServices = { storageGet, storageSet, storageRemove, storageClear, storageKeys };

installStorageServices(nativeStorageServices);
