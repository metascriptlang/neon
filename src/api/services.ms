export interface AlertButtonSpec {
	text: string;
	style: string;
}

export const ALERT_DISMISSED: int32 = -1;

export interface AlertRequest {
	title: string;
	message: string;
	buttons: AlertButtonSpec[];
	cancelable: boolean;
	done: (index: int32) => void;
}

export interface ShareRequest {
	title: string;
	message: string;
	url: string;
	done: (action: string, activityType: string) => void;
}

export interface AppServices {
	dismissKeyboard: () => void;
	alert: (request: AlertRequest) => void;
	openURL: (url: string) => Promise<boolean>;
	canOpenURL: (url: string) => Promise<boolean>;
	initialURL: () => Promise<string>;
	openSettings: () => Promise<boolean>;
	share: (request: ShareRequest) => void;
	vibrate: (pattern: int32[], repeat: boolean) => void;
	cancelVibration: () => void;
	getClipboard: () => Promise<string>;
	setClipboard: (text: string) => void;
	screenReaderEnabled: () => Promise<boolean>;
	reduceMotionEnabled: () => Promise<boolean>;
	announce: (text: string) => void;
	exitApp: () => void;
	// Loads an image into the platform's image cache and reports its pixel size; a failure
	// reports an error message and a 0 x 0 size.
	imageSize: (uri: string, done: (width: number, height: number, error: string) => void) => void;
}

let installed: AppServices | null = null;

export function installAppServices(services: AppServices | null): void {
	installed = services;
}

export function appServices(api: string): AppServices {
	const services = installed;
	if (services === null) {
		throw new Error(
			api + ": no host has installed app services; start the app through runApp or domHost",
		);
	}
	return services;
}

export function hasAppServices(): boolean {
	return installed !== null;
}
