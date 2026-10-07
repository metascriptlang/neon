import { NetInfoState, NetInfoStateType, publishNetInfo } from "../../api/netInfo";
import { LocationFix, LocationRequest, PermissionReply } from "../../api/services";

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
extern class BrowserCoordinates {
	latitude: number;
	longitude: number;
	altitude: number;
	accuracy: number;
	altitudeAccuracy: number;
	heading: number;
	speed: number;
}

extern class BrowserPosition {
	coords: BrowserCoordinates;
	timestamp: number;
}

extern class BrowserPositionError {
	code: number;
	message: string;
}

interface BrowserPositionOptions {
	enableHighAccuracy: boolean;
	timeout: number;
	maximumAge: number;
}

extern class BrowserGeolocation {
	extern getCurrentPosition(
		ok: (p: BrowserPosition) => void,
		fail: (e: BrowserPositionError) => void,
		options: BrowserPositionOptions,
	): void;
	extern watchPosition(
		ok: (p: BrowserPosition) => void,
		fail: (e: BrowserPositionError) => void,
		options: BrowserPositionOptions,
	): number;
	extern clearWatch(id: number): void;
}

extern function geolocation(unused: int32): BrowserGeolocation | null from "(#, navigator.geolocation || null)";
extern function measured(value: number): number from "((v) => typeof v === 'number' && Number.isFinite(v) ? v : NaN)(#)";
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

function browserFix(position: BrowserPosition): LocationFix {
	const coords = position.coords;
	return {
		code: 0,
		message: "",
		latitude: coords.latitude,
		longitude: coords.longitude,
		altitude: measured(coords.altitude),
		accuracy: measured(coords.accuracy),
		altitudeAccuracy: measured(coords.altitudeAccuracy),
		heading: measured(coords.heading),
		speed: measured(coords.speed),
		timestamp: position.timestamp,
	};
}

function browserFailure(code: number, message: string): LocationFix {
	return {
		code: code as int32,
		message,
		latitude: 0,
		longitude: 0,
		altitude: NaN,
		accuracy: NaN,
		altitudeAccuracy: NaN,
		heading: NaN,
		speed: NaN,
		timestamp: 0,
	};
}

function browserOptions(request: LocationRequest): BrowserPositionOptions {
	return {
		enableHighAccuracy: request.highAccuracy,
		timeout: request.timeout < 0 ? Infinity : request.timeout,
		maximumAge: request.maximumAge < 0 ? Infinity : request.maximumAge,
	};
}

const browserWatchIds: int32[] = [];
const browserWatchHandles: number[] = [];

export function locationCurrent(request: LocationRequest, done: (fix: LocationFix) => void): void {
	const located = geolocation(0);
	if (located === null) {
		done(browserFailure(2, "Geolocation is not supported in this browser"));
		return;
	}
	located.getCurrentPosition(
		(position: BrowserPosition): void => { done(browserFix(position)); },
		(error: BrowserPositionError): void => { done(browserFailure(error.code, error.message)); },
		browserOptions(request),
	);
}

export function locationWatch(id: int32, request: LocationRequest, update: (fix: LocationFix) => void): void {
	const located = geolocation(0);
	if (located === null) {
		update(browserFailure(2, "Geolocation is not supported in this browser"));
		return;
	}
	const handle = located.watchPosition(
		(position: BrowserPosition): void => { update(browserFix(position)); },
		(error: BrowserPositionError): void => { update(browserFailure(error.code, error.message)); },
		browserOptions(request),
	);
	browserWatchIds.push(id);
	browserWatchHandles.push(handle);
}

export function locationClear(id: int32): void {
	const at = browserWatchIds.indexOf(id);
	const located = geolocation(0);
	if (at < 0 || located === null) { return; }
	located.clearWatch(browserWatchHandles[at]);
	browserWatchIds.splice(at, 1);
	browserWatchHandles.splice(at, 1);
}
