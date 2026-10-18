// The app services of every Ion host, the full-window <Void> and the Windows native host alike.
// Ion backs the clipboard and the microphone and camera permissions; a service Ion does not back yet is refused with the name the
// author called.

import {
	AlertRequest, AppServices, BatterySnapshot, DeviceSnapshot, LocaleSnapshot, LocationFix, LocationRequest,
	PermissionReply, ShareRequest,
} from "../../api/services";
import { readClipboardText, writeClipboardText } from "../../../../ion/src/clipboard";
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

export const ionAppServices: AppServices = {
	dismissKeyboard: (): void => { throw unavailable("Keyboard.dismiss"); },
	alert: (request: AlertRequest): void => { throw unavailable("Alert.alert"); },
	openURL: async (url: string): Promise<boolean> => { throw unavailable("Linking.openURL"); },
	canOpenURL: async (url: string): Promise<boolean> => { throw unavailable("Linking.canOpenURL"); },
	initialURL: async (): Promise<string> => { throw unavailable("Linking.getInitialURL"); },
	openSettings: async (): Promise<boolean> => { throw unavailable("Linking.openSettings"); },
	share: (request: ShareRequest): void => { throw unavailable("Share.share"); },
	vibrate: (pattern: int32[], repeat: boolean): void => { throw unavailable("Vibration.vibrate"); },
	cancelVibration: (): void => { throw unavailable("Vibration.cancel"); },
	getClipboard: async (): Promise<string> => { return readClipboardText(); },
	setClipboard: (text: string): void => {
		if (!writeClipboardText(text)) { throw new Error("Clipboard.setString: the OS refused the clipboard write"); }
	},
	screenReaderEnabled: async (): Promise<boolean> => { throw unavailable("AccessibilityInfo.isScreenReaderEnabled"); },
	reduceMotionEnabled: async (): Promise<boolean> => { throw unavailable("AccessibilityInfo.isReduceMotionEnabled"); },
	announce: (text: string): void => { throw unavailable("AccessibilityInfo.announceForAccessibility"); },
	exitApp: (): void => { throw unavailable("BackHandler.exitApp"); },
	imageSize: (uri: string, done: (width: number, height: number, error: string) => void): void => { throw unavailable("Image.getSize"); },
	storageGet: (key: string): string | null => { throw unavailable("AsyncStorage"); },
	storageSet: (key: string, value: string): void => { throw unavailable("AsyncStorage"); },
	storageRemove: (key: string): void => { throw unavailable("AsyncStorage"); },
	storageClear: (): void => { throw unavailable("AsyncStorage"); },
	storageKeys: (): string[] => { throw unavailable("AsyncStorage"); },
	watchNetInfo: (): void => { throw unavailable("NetInfo"); },
	refreshNetInfo: (): void => { throw unavailable("NetInfo"); },
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
	locationCurrent: (request: LocationRequest, done: (fix: LocationFix) => void): void => { throw unavailable("Geolocation"); },
	locationWatch: (id: int32, request: LocationRequest, update: (fix: LocationFix) => void): void => { throw unavailable("Geolocation"); },
	locationClear: (id: int32): void => { throw unavailable("Geolocation"); },
	haptic: (kind: string, style: string): void => { throw unavailable("Haptics"); },
	deviceInfo: (): DeviceSnapshot => { throw unavailable("DeviceInfo"); },
	battery: async (): Promise<BatterySnapshot> => { throw unavailable("DeviceInfo battery"); },
	localization: (): LocaleSnapshot => { throw unavailable("Localization"); },
};
