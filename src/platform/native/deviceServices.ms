import { niAppCall } from "./app.h";
import { NetInfoDetails, NetInfoState, NetInfoStateType, publishNetInfo } from "../../api/netInfo";
import { TextSlot } from "../../api/replySlot";
import {
	BatterySnapshot, DeviceSnapshot, LocaleSnapshot, LocationFix, LocationRequest, NotificationSpec, PermissionReply,
	ScheduleReply,
} from "../../api/services";
import { decodeLocalization } from "../../api/hostCodec";

const FIELD = "\u001f";
const RECORD = "\u001e";
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

function flag(text: string): boolean | null {
	if (text === "") { return null; }
	return text === "1";
}

export function decodeNetInfo(value: string): NetInfoState {
	const fields = value.split(FIELD);
	if (fields.length !== 4) { throw new Error("NetInfo: the host sent a malformed state: " + value); }
	const type = fields[0] as NetInfoStateType;
	const connected = flag(fields[1]);
	const details: NetInfoDetails | null = connected === true ? { isConnectionExpensive: fields[3] === "1" } : null;
	return { type, isConnected: connected, isInternetReachable: flag(fields[2]), details };
}

export function watchNetInfo(): void {
	publishNetInfo(decodeNetInfo(call("netinfo.watch", "")));
}

export function refreshNetInfo(): void {
	publishNetInfo(decodeNetInfo(call("netinfo.fetch", "")));
}

export function onNetInfoEvent(value: string): void {
	publishNetInfo(decodeNetInfo(value));
}

interface PendingReply {
	id: int32;
	done: (reply: string) => void;
}

const replies: PendingReply[] = [];
let nextReply: int32 = 1;

export function requestReply(name: string, arg: string, done: (reply: string) => void): void {
	const id = nextReply;
	nextReply += 1;
	const reply = call(name, id.toString() + FIELD + arg);
	if (reply !== "") {
		done(reply);
		return;
	}
	replies.push({ id, done });
}

export async function ask(name: string, arg: string): Promise<string> {
	const slot = new TextSlot();
	requestReply(name, arg, (reply: string): void => { slot.settle(reply); });
	return await slot.wait();
}

export function onReplyEvent(value: string): void {
	const split = value.indexOf(FIELD);
	const id = parseInt(split < 0 ? value : value.substring(0, split)) as int32;
	const reply = split < 0 ? "" : value.substring(split + 1, value.length);
	for (let i = 0; i < replies.length; i += 1) {
		if (replies[i].id === id) {
			const pending = replies[i];
			replies.splice(i, 1);
			pending.done(reply);
			return;
		}
	}
}

function refusal(reply: string): string {
	return reply.startsWith("!") ? reply.substring(1, reply.length) : "";
}

function permissionReply(reply: string): PermissionReply {
	const error = refusal(reply);
	if (error !== "") { return { status: "", canAskAgain: false, error }; }
	const fields = reply.split(FIELD);
	return { status: fields[0], canAskAgain: fields.length > 1 && fields[1] === "1", error: "" };
}

export async function permissionStatus(name: string): Promise<PermissionReply> {
	return permissionReply(await ask("permission.check", name));
}

export async function requestPermission(name: string): Promise<PermissionReply> {
	return permissionReply(await ask("permission.request", name));
}

export async function androidPermissionGranted(permission: string): Promise<boolean> {
	return call("permissionsAndroid.check", permission) === "1";
}

export async function androidShouldShowRationale(permission: string): Promise<boolean> {
	return call("permissionsAndroid.rationale", permission) === "1";
}

export async function androidRequestPermissions(permissions: string[]): Promise<PermissionReply[]> {
	const reply = await ask("permissionsAndroid.request", permissions.join(","));
	const error = refusal(reply);
	const results: PermissionReply[] = [];
	const fields = reply.split(FIELD);
	for (let i = 0; i < permissions.length; i += 1) {
		const status = error === "" && i < fields.length ? fields[i] : "";
		results.push({ status, canAskAgain: false, error });
	}
	return results;
}

function measured(text: string): number {
	return text === "" ? NaN : parseFloat(text);
}

export function decodeFix(value: string): LocationFix {
	const fields = value.split(FIELD);
	if (fields[0] === "error" && fields.length === 3) {
		return {
			code: parseInt(fields[1]) as int32,
			message: fields[2],
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
	if (fields[0] !== "ok" || fields.length !== 9) {
		throw new Error("Geolocation: the host sent a malformed fix: " + value);
	}
	return {
		code: 0,
		message: "",
		latitude: parseFloat(fields[1]),
		longitude: parseFloat(fields[2]),
		altitude: measured(fields[3]),
		accuracy: measured(fields[4]),
		altitudeAccuracy: measured(fields[5]),
		heading: measured(fields[6]),
		speed: measured(fields[7]),
		timestamp: parseFloat(fields[8]),
	};
}

function encodeRequest(request: LocationRequest): string {
	return (request.highAccuracy ? "1" : "0") + FIELD + request.timeout.toString() + FIELD +
		request.maximumAge.toString() + FIELD + request.distanceFilter.toString() + FIELD + request.interval.toString();
}

interface LocationWatch {
	id: int32;
	update: (fix: LocationFix) => void;
}

const watches: LocationWatch[] = [];

export function locationCurrent(request: LocationRequest, done: (fix: LocationFix) => void): void {
	requestReply("location.current", encodeRequest(request), (reply: string): void => { done(decodeFix(reply)); });
}

export function locationWatch(id: int32, request: LocationRequest, update: (fix: LocationFix) => void): void {
	watches.push({ id, update });
	call("location.watch", id.toString() + FIELD + encodeRequest(request));
}

export function locationClear(id: int32): void {
	for (let i = 0; i < watches.length; i += 1) {
		if (watches[i].id === id) {
			watches.splice(i, 1);
			call("location.clear", id.toString());
			return;
		}
	}
}

export function onLocationEvent(value: string): void {
	const split = value.indexOf(FIELD);
	const id = parseInt(value.substring(0, split)) as int32;
	for (const watch of watches.slice(0, watches.length)) {
		if (watch.id === id) { watch.update(decodeFix(value.substring(split + 1, value.length))); }
	}
}

export function haptic(kind: string, style: string): void {
	call("haptics." + kind, style);
}

export function decodeDevice(value: string): DeviceSnapshot {
	const fields = value.split(FIELD);
	if (fields.length !== 12) { throw new Error("DeviceInfo: the host sent malformed device info: " + value); }
	return {
		brand: fields[0],
		manufacturer: fields[1],
		model: fields[2],
		deviceId: fields[3],
		systemName: fields[4],
		systemVersion: fields[5],
		applicationName: fields[6],
		bundleId: fields[7],
		version: fields[8],
		buildNumber: fields[9],
		isEmulator: fields[10] === "1",
		isTablet: fields[11] === "1",
	};
}

export function deviceInfo(): DeviceSnapshot {
	return decodeDevice(call("device.info", ""));
}

export async function battery(): Promise<BatterySnapshot> {
	const fields = (await ask("device.battery", "")).split(FIELD);
	return { level: fields[0] === "" ? -1 : parseFloat(fields[0]), charging: fields.length > 1 && fields[1] === "1" };
}

export function localization(): LocaleSnapshot {
	return decodeLocalization(call("locale.info", ""));
}

function flagText(value: boolean): string {
	return value ? "1" : "0";
}

export async function scheduleNotification(spec: NotificationSpec): Promise<ScheduleReply> {
	const reply = await ask("notification.schedule", [
		spec.identifier, spec.title, spec.subtitle, spec.body, spec.data, flagText(spec.sound), spec.badge.toString(),
		spec.seconds.toString(), flagText(spec.repeats), spec.date.toString(),
	].join(FIELD));
	const error = refusal(reply);
	return { identifier: error === "" ? reply : "", error };
}

export function cancelNotification(identifier: string): void {
	call("notification.cancel", identifier);
}

export function cancelAllNotifications(): void {
	call("notification.cancelAll", "");
}

export function dismissAllNotifications(): void {
	call("notification.dismissAll", "");
}

export function presentNotifications(decide: boolean): void {
	call("notification.handler", flagText(decide));
}

export function presentNotification(identifier: string, banner: boolean, sound: boolean, badge: boolean): void {
	call("notification.present", [identifier, flagText(banner), flagText(sound), flagText(badge)].join(FIELD));
}

export async function lastNotificationResponse(): Promise<string> {
	return call("notification.last", "");
}

export function installNotifications(): void {
	call("notification.install", "");
}
