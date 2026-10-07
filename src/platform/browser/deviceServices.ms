import { NetInfoState, NetInfoStateType, publishNetInfo } from "../../api/netInfo";
import { PermissionReply } from "../../api/services";

extern class DeviceEvent {}

extern class window {
	static extern addEventListener(name: cstring, handler: (e: DeviceEvent) => void): void;
}

extern class navigator {
	static onLine: boolean;
}

extern function permissionQuery(name: cstring): Promise<string> from "(navigator.permissions ? navigator.permissions.query({ name: # }).then((s) => s.state, () => 'prompt') : Promise.resolve('prompt'))";
extern function askNotifications(unused: int32): Promise<string> from "(#, typeof Notification === 'undefined' ? Promise.resolve('denied') : Promise.resolve(Notification.requestPermission()))";
extern function askMedia(video: boolean): Promise<string> from "(navigator.mediaDevices ? navigator.mediaDevices.getUserMedia(# ? { video: true } : { audio: true }).then((s) => { s.getTracks().forEach((t) => t.stop()); return 'granted'; }, () => 'denied') : Promise.resolve('denied'))";
extern function askGeolocation(unused: int32): Promise<string> from "(#, new Promise((resolve) => navigator.geolocation ? navigator.geolocation.getCurrentPosition(() => resolve('granted'), (e) => resolve(e.code === 1 ? 'denied' : 'granted')) : resolve('denied')))";
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

function browserPermission(name: string): string {
	return match (name) {
		"camera" => "camera",
		"microphone" => "microphone",
		"location" => "geolocation",
		"notifications" => "notifications",
		_ => "",
	};
}

function permissionReply(state: string): PermissionReply {
	return match (state) {
		"granted" => ({ status: "granted", canAskAgain: false, error: "" }),
		"denied" => ({ status: "denied", canAskAgain: false, error: "" }),
		_ => ({ status: "undetermined", canAskAgain: true, error: "" }),
	};
}

export async function permissionStatus(name: string): Promise<PermissionReply> {
	const browserName = browserPermission(name);
	if (browserName === "") { return { status: "", canAskAgain: false, error: "Permissions: unknown permission " + name }; }
	return permissionReply(await permissionQuery(browserName));
}

export async function requestPermission(name: string): Promise<PermissionReply> {
	const now = await permissionStatus(name);
	if (now.status !== "undetermined" || now.error !== "") { return now; }
	const answer: string = match (name) {
		"notifications" => await askNotifications(0),
		"camera" => await askMedia(true),
		"microphone" => await askMedia(false),
		_ => await askGeolocation(0),
	};
	return permissionReply(answer === "default" ? "prompt" : answer);
}

export async function androidPermissionGranted(permission: string): Promise<boolean> {
	return false;
}

export async function androidShouldShowRationale(permission: string): Promise<boolean> {
	return false;
}

export async function androidRequestPermissions(permissions: string[]): Promise<PermissionReply[]> {
	const denied: PermissionReply[] = [];
	for (const permission of permissions) { denied.push({ status: "denied", canAskAgain: false, error: "" }); }
	return denied;
}
