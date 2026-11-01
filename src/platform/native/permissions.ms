import { PermissionReply, PermissionServices, installPermissionServices } from "../../api/permissionServices";
import { AppCommand, FIELD, appCall, ask, refusal, wireFields } from "./appBridge";
import { niPermissionCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/permissions.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
	@compile("../ios/location.m", "-fobjc-arc");
	@passL("-framework AVFoundation");
	@passL("-framework CoreLocation");
	@passL("-framework UserNotifications");
} else when (android) {
	androidLibrary("../android/permissions");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		return niPermissionCommand(name, arg);
	}
} else {
	const command: AppCommand = appCall;
}

function permissionReply(reply: string): PermissionReply {
	const error = refusal(reply);
	if (error !== "") { throw new Error(error); }
	const fields = reply.split(FIELD);
	return { status: fields[0], canAskAgain: fields.length > 1 && fields[1] === "1" };
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
	if (error !== "") { throw new Error(error); }
	const results: PermissionReply[] = [];
	const fields = wireFields("Permissions", reply, permissions.length);
	for (let i = 0; i < permissions.length; i += 1) {
		results.push({ status: fields[i], canAskAgain: false });
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
