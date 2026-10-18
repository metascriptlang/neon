import { PermissionReply, PermissionServices, installPermissionServices } from "../../api/permissionServices";
import {
	MediaAccess, cameraAccess, microphoneAccess, requestCameraAccess, requestMicrophoneAccess,
} from "../../../../ion/src/permission";

function unavailable(api: string): Error {
	return new Error(`${api} is not available on an Ion desktop host yet`);
}

function refusedPermission(name: string): PermissionReply {
	return { status: "", canAskAgain: false, error: `Permissions(${name}) is not available on an Ion desktop host yet` };
}

function accessReply(got: Result<MediaAccess, string>): PermissionReply {
	if (!got.ok) { return { status: "", canAskAgain: false, error: got.error }; }
	return { status: got.value.status, canAskAgain: got.value.canAskAgain, error: "" };
}

export const ionPermissionServices: PermissionServices = {
	permissionStatus: async (name: string): Promise<PermissionReply> => {
		if (name === "microphone") { return accessReply(microphoneAccess()); }
		if (name === "camera") { return accessReply(cameraAccess()); }
		return refusedPermission(name);
	},
	requestPermission: async (name: string): Promise<PermissionReply> => {
		if (name === "microphone") {
			const got = await requestMicrophoneAccess();
			return accessReply(got);
		}
		if (name === "camera") {
			const got = await requestCameraAccess();
			return accessReply(got);
		}
		return refusedPermission(name);
	},
	androidPermissionGranted: async (p: string): Promise<boolean> => { throw unavailable("PermissionsAndroid"); },
	androidShouldShowRationale: async (p: string): Promise<boolean> => { throw unavailable("PermissionsAndroid"); },
	androidRequestPermissions: async (p: string[]): Promise<PermissionReply[]> => { throw unavailable("PermissionsAndroid"); },
};

installPermissionServices(ionPermissionServices);
