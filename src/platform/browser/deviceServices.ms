import { NetInfoState, NetInfoStateType, publishNetInfo } from "../../api/netInfo";

extern class DeviceEvent {}

extern class window {
	static extern addEventListener(name: cstring, handler: (e: DeviceEvent) => void): void;
}

extern class navigator {
	static onLine: boolean;
}

extern function connectionType(unused: int32): string from "(#, String((navigator.connection && navigator.connection.type) || ''))";
extern function connectionSavesData(unused: int32): boolean from "(#, Boolean(navigator.connection && navigator.connection.saveData))";

extern class localStorage {
	static length: number;
	static extern setItem(key: cstring, value: cstring): void;
	static extern removeItem(key: cstring): void;
	static extern clear(): void;
}

extern function storageHas(key: cstring): boolean from "(localStorage.getItem(#) !== null)";
extern function storageRead(key: cstring): string from "(localStorage.getItem(#) ?? '')";
extern function storageKeyAt(index: number): string from "(localStorage.key(#) ?? '')";

export function storageGet(key: string): string | null {
	return storageHas(key) ? storageRead(key) : null;
}

export function storageSet(key: string, value: string): void {
	localStorage.setItem(key, value);
}

export function storageRemove(key: string): void {
	localStorage.removeItem(key);
}

export function storageClear(): void {
	localStorage.clear();
}

export function storageKeys(): string[] {
	const keys: string[] = [];
	const count = localStorage.length;
	for (let i = 0; i < count; i += 1) { keys.push(storageKeyAt(i)); }
	return keys;
}

const NETINFO_TYPES = ["none", "cellular", "wifi", "bluetooth", "ethernet", "wimax", "vpn", "other"];

function netInfoNow(): NetInfoState {
	if (!navigator.onLine) {
		return { type: "none", isConnected: false, isInternetReachable: false, details: null };
	}
	const reported = connectionType(0);
	const type: string = NETINFO_TYPES.indexOf(reported) > 0 ? reported : "unknown";
	return {
		type: type as NetInfoStateType,
		isConnected: true,
		isInternetReachable: true,
		details: { isConnectionExpensive: connectionSavesData(0) || type === "cellular" },
	};
}

export function watchNetInfo(): void {
	publishNetInfo(netInfoNow());
	window.addEventListener("online", (e: DeviceEvent): void => { publishNetInfo(netInfoNow()); });
	window.addEventListener("offline", (e: DeviceEvent): void => { publishNetInfo(netInfoNow()); });
}

export function refreshNetInfo(): void {
	publishNetInfo(netInfoNow());
}
