import { FIELD, appCall, ask as appAsk, refusal } from "./appBridge";
import {
	PermissionReply,
} from "../../api/services";

function call(name: string, arg: string): string {
	return appCall(name, arg);
}

async function ask(name: string, arg: string): Promise<string> {
	const reply = await appAsk(appCall, name, arg);
	return reply;
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
