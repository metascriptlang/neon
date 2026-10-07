import { niAppCall } from "./app.h";
import { NetInfoDetails, NetInfoState, NetInfoStateType, publishNetInfo } from "../../api/netInfo";
import { TextSlot } from "../../api/replySlot";
import { PermissionReply } from "../../api/services";

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

export function request(name: string, arg: string, done: (reply: string) => void): void {
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
	request(name, arg, (reply: string): void => { slot.settle(reply); });
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
