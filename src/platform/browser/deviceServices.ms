import { NetInfoState, NetInfoStateType, publishNetInfo } from "../../api/netInfo";
import {
	BatterySnapshot, DeviceSnapshot, LocaleSnapshot, LocationFix, LocationRequest, PermissionReply,
} from "../../api/services";
import { decodeLocalization } from "../../api/hostCodec";
import { NotificationSpec, ScheduleReply } from "../../api/services";
import { publishNotificationEvent } from "../../api/notifications";

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
extern function vibrateFor(pattern: cstring): boolean from "(typeof navigator.vibrate === 'function' ? navigator.vibrate(JSON.parse(#)) : false)";
extern function localeReport(unused: int32): string from "(#, (() => { const F = String.fromCharCode(31); const R = String.fromCharCode(30); const fahrenheit = ['US', 'BS', 'BZ', 'KY', 'PW', 'LR']; const tags = (navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || 'en-US']); const options = new Intl.DateTimeFormat().resolvedOptions(); const cycle = new Intl.DateTimeFormat(undefined, { hour: 'numeric' }).resolvedOptions().hourCycle; const first = new Intl.Locale(tags[0]); const week = first.getWeekInfo ? first.getWeekInfo() : first.weekInfo; const firstWeekday = week && week.firstDay ? (week.firstDay % 7) + 1 : 1; const records = [[options.calendar || '', options.timeZone || '', cycle === 'h23' || cycle === 'h24' ? '1' : '0', String(firstWeekday)].join(F)]; for (const tag of tags) { const locale = new Intl.Locale(tag); const info = locale.getTextInfo ? locale.getTextInfo() : locale.textInfo; const parts = new Intl.NumberFormat(tag).formatToParts(12345.6); const part = (type) => (parts.find((p) => p.type === type) || { value: '' }).value; const region = locale.region || ''; const measurement = region === '' ? '' : region === 'US' || region === 'LR' || region === 'MM' ? 'us' : region === 'GB' ? 'uk' : 'metric'; records.push([tag, locale.language || '', locale.script || '', region, info && info.direction ? info.direction : '', part('decimal'), part('group'), measurement, '', '', region === '' ? '' : fahrenheit.includes(region) ? 'fahrenheit' : 'celsius'].join(F)); } return records.join(R); })())";
extern function batteryReport(unused: int32): Promise<string> from "(#, navigator.getBattery ? navigator.getBattery().then((b) => b.level + ',' + (b.charging ? '1' : '0'), () => '-1,0') : Promise.resolve('-1,0'))";
extern function documentTitle(unused: int32): string from "(#, document.title || '')";
extern function pageHost(unused: int32): string from "(#, location.host || '')";
extern function notificationPermission(unused: int32): string from "(#, typeof Notification === 'undefined' ? 'unsupported' : Notification.permission)";
extern function pageVisible(unused: int32): boolean from "(#, document.visibilityState === 'visible')";
extern function showNotification(title: cstring, body: cstring, tag: cstring, onClick: () => void): boolean from "((title, body, tag, onClick) => { const n = new Notification(title, { body, tag }); n.onclick = () => onClick(); (window.__neonNotifications = window.__neonNotifications || []).push(n); return true; })(#, #, #, #)";
extern function closeNotifications(unused: int32): void from "(#, (window.__neonNotifications || []).splice(0).forEach((n) => n.close()))";
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

export function haptic(kind: string, style: string): void {
	const pattern = match (kind + "." + style) {
		"impact.light" => "[10]",
		"impact.soft" => "[10]",
		"impact.heavy" => "[30]",
		"impact.rigid" => "[15]",
		"notification.success" => "[10,40,20]",
		"notification.warning" => "[20,60,20]",
		"notification.error" => "[30,40,30,40,30]",
		"selection." => "[5]",
		_ => "[20]",
	};
	vibrateFor(pattern);
}

export function deviceInfo(): DeviceSnapshot {
	return {
		brand: "",
		manufacturer: "",
		model: "",
		deviceId: "",
		systemName: "",
		systemVersion: "",
		applicationName: documentTitle(0),
		bundleId: pageHost(0),
		version: "",
		buildNumber: "",
		isEmulator: false,
		isTablet: false,
	};
}

export async function battery(): Promise<BatterySnapshot> {
	const fields = (await batteryReport(0)).split(",");
	return { level: parseFloat(fields[0]), charging: fields[1] === "1" };
}

export function localization(): LocaleSnapshot {
	return decodeLocalization(localeReport(0));
}

const NOTIFICATION_FIELD = "\u001f";

interface BrowserScheduled {
	spec: NotificationSpec;
	timer: int32;
}

const scheduled: BrowserScheduled[] = [];
const awaitingPresentation: NotificationSpec[] = [];
let decidesPresentation = false;

function notificationRecord(kind: string, spec: NotificationSpec): string {
	return [kind, spec.identifier, spec.title, spec.subtitle, spec.body, spec.data, Date.now().toString()].join(NOTIFICATION_FIELD);
}

function show(spec: NotificationSpec): void {
	showNotification(spec.title, spec.body, spec.identifier, (): void => {
		publishNotificationEvent(notificationRecord("response", spec));
	});
}

function deliver(spec: NotificationSpec): void {
	if (!pageVisible(0)) {
		show(spec);
		return;
	}
	if (decidesPresentation) { awaitingPresentation.push(spec); }
	publishNotificationEvent(notificationRecord("received", spec));
}

function forget(identifier: string): void {
	for (let i = 0; i < scheduled.length; i += 1) {
		if (scheduled[i].spec.identifier === identifier) {
			clearTimeout(scheduled[i].timer);
			scheduled.splice(i, 1);
			return;
		}
	}
}

function arm(spec: NotificationSpec, delay: number): void {
	const timer = setTimeout((): void => {
		forget(spec.identifier);
		deliver(spec);
		if (spec.repeats) { arm(spec, spec.seconds * 1000); }
	}, delay) as int32;
	scheduled.push({ spec, timer });
}

export async function scheduleNotification(spec: NotificationSpec): Promise<ScheduleReply> {
	const permission = notificationPermission(0);
	if (permission === "unsupported") {
		return { identifier: "", error: "Notifications are not supported in this browser" };
	}
	if (permission !== "granted") {
		return { identifier: "", error: "Notifications.scheduleNotificationAsync: notification permission is " + permission };
	}
	forget(spec.identifier);
	const delay = spec.date >= 0 ? Math.max(0, spec.date - Date.now()) : Math.max(0, spec.seconds) * 1000;
	if (spec.seconds < 0 && spec.date < 0) {
		deliver(spec);
	} else {
		arm(spec, delay);
	}
	return { identifier: spec.identifier, error: "" };
}

export function cancelNotification(identifier: string): void {
	forget(identifier);
}

export function cancelAllNotifications(): void {
	for (const entry of scheduled.slice(0, scheduled.length)) { forget(entry.spec.identifier); }
}

export function dismissAllNotifications(): void {
	closeNotifications(0);
}

export function presentNotifications(decide: boolean): void {
	decidesPresentation = decide;
}

export function presentNotification(identifier: string, banner: boolean, sound: boolean, badge: boolean): void {
	for (let i = 0; i < awaitingPresentation.length; i += 1) {
		if (awaitingPresentation[i].identifier === identifier) {
			const spec = awaitingPresentation[i];
			awaitingPresentation.splice(i, 1);
			if (banner) { show(spec); }
			return;
		}
	}
}

export async function lastNotificationResponse(): Promise<string> {
	return "";
}
