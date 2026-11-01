import { StorageServices, installStorageServices } from "../../api/storageServices";
import { AppCommand, FIELD, appCall, presentValue } from "./appBridge";
import { niStorageCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/storage.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/storage");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		return niStorageCommand(name, arg) as string;
	}
} else {
	const command: AppCommand = appCall;
}

function storageGet(key: string): string | null {
	return presentValue(command("storage.get", key));
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
