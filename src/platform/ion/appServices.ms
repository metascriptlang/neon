// The app services of every Ion host, the full-window <Void> and the Windows native host alike.
// Ion backs the clipboard and the microphone and camera permissions; a service Ion does not back yet is refused with the name the
// author called.

import {
	AlertRequest, AppServices, ShareRequest,
} from "../../api/services";

function unavailable(api: string): Error {
	return new Error(`${api} is not available on an Ion desktop host yet`);
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
	screenReaderEnabled: async (): Promise<boolean> => { throw unavailable("AccessibilityInfo.isScreenReaderEnabled"); },
	reduceMotionEnabled: async (): Promise<boolean> => { throw unavailable("AccessibilityInfo.isReduceMotionEnabled"); },
	announce: (text: string): void => { throw unavailable("AccessibilityInfo.announceForAccessibility"); },
	exitApp: (): void => { throw unavailable("BackHandler.exitApp"); },
	imageSize: (uri: string, done: (width: number, height: number, error: string) => void): void => { throw unavailable("Image.getSize"); },
};
