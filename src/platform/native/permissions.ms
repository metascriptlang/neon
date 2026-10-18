import { PermissionReply, PermissionServices, installPermissionServices } from "../../api/permissionServices";
import { FIELD, appCall, ask, refusal } from "./appBridge";
import { niPermissionCommand } from "../ios/commands.h";

when (ios) {
	@compile("../ios/permissions.m", "-fobjc-arc");
	@compile("../ios/location.m", "-fobjc-arc");
	@passL("-framework AVFoundation");
	@passL("-framework CoreLocation");
	@passL("-framework UserNotifications");

	function command(name: string, arg: string): string {
		const reply: string = niPermissionCommand(name, arg);
		return reply;
	}
} else {
	function command(name: string, arg: string): string {
		return appCall(name, arg);
	}
}

function permissionReply(reply: string): PermissionReply {
	const error = refusal(reply);
	if (error !== "") { return { status: "", canAskAgain: false, error }; }
	const fields = reply.split(FIELD);
	return { status: fields[0], canAskAgain: fields.length > 1 && fields[1] === "1", error: "" };
}

async function permissionStatus(name: string): Promise<PermissionReply> {
	return permissionReply(await ask(command, "permission.check", name));
}

async function requestPermission(name: string): Promise<PermissionReply> {
	return permissionReply(await ask(command, "permission.request", name));
}

async function androidPermissionGranted(permission: string): Promise<boolean> {
	return command("permissionsAndroid.check", permission) === "1";
}

async function androidShouldShowRationale(permission: string): Promise<boolean> {
	return command("permissionsAndroid.rationale", permission) === "1";
}

async function androidRequestPermissions(permissions: string[]): Promise<PermissionReply[]> {
	const reply = await ask(command, "permissionsAndroid.request", permissions.join(","));
	const error = refusal(reply);
	const results: PermissionReply[] = [];
	const fields = reply.split(FIELD);
	for (let i = 0; i < permissions.length; i += 1) {
		const status = error === "" && i < fields.length ? fields[i] : "";
		results.push({ status, canAskAgain: false, error });
	}
	return results;
}

export const nativePermissionServices: PermissionServices = {
	permissionStatus,
	requestPermission,
	androidPermissionGranted,
	androidShouldShowRationale,
	androidRequestPermissions,
};

installPermissionServices(nativePermissionServices);
