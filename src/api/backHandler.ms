import { EventSubscription } from "./subscription";
import { appServices } from "./services";

interface BackEntry {
	id: int32;
	handler: () => boolean;
}

const entries: BackEntry[] = [];
let nextId: int32 = 1;

export class BackHandler {
	static addEventListener(
		eventName: "hardwareBackPress",
		handler: () => boolean,
	): EventSubscription {
		const id = nextId;
		nextId += 1;
		entries.push({ id, handler });
		return {
			remove: (): void => {
				for (let i = 0; i < entries.length; i += 1) {
					if (entries[i].id === id) {
						entries.splice(i, 1);
						return;
					}
				}
			},
		};
	}

	static exitApp(): void {
		appServices("BackHandler.exitApp").exitApp();
	}
}

export function dispatchHardwareBackPress(): boolean {
	const snapshot = entries.slice(0, entries.length);
	for (let i = snapshot.length - 1; i >= 0; i -= 1) {
		if (snapshot[i].handler()) { return true; }
	}
	return false;
}
