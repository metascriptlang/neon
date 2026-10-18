// The app services of every Ion host, the full-window <Void> and the Windows native host alike.
// Ion backs none of the host-bound services yet: each is refused with the name the author called.

import {
	AlertRequest, AppServices, ShareRequest,
} from "../../api/services";

function unavailable(api: string): Error {
	return new Error(`${api} is not available on an Ion desktop host yet`);
}

export const ionAppServices: AppServices = {
	dismissKeyboard: (): void => { throw unavailable("Keyboard.dismiss"); },
	alert: (request: AlertRequest): void => { throw unavailable("Alert.alert"); },
	share: (request: ShareRequest): void => { throw unavailable("Share.share"); },
	announce: (text: string): void => { throw unavailable("AccessibilityInfo.announceForAccessibility"); },
	exitApp: (): void => { throw unavailable("BackHandler.exitApp"); },
	imageSize: (uri: string, done: (width: number, height: number, error: string) => void): void => { throw unavailable("Image.getSize"); },
};
