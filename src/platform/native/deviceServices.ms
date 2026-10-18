import { FIELD, appCall, ask as appAsk, refusal } from "./appBridge";
import { NetInfoDetails, NetInfoState, NetInfoStateType, publishNetInfo } from "../../api/netInfo";
import {
	BatterySnapshot, DeviceSnapshot, LocaleSnapshot, PermissionReply,
} from "../../api/services";
import { decodeLocalization } from "../../api/hostCodec";

const PRESENT = "=";

function call(name: string, arg: string): string {
	return appCall(name, arg);
}

async function ask(name: string, arg: string): Promise<string> {
	const reply = await appAsk(appCall, name, arg);
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
