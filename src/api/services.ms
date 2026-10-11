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

// A host refusal travels as `error`, not as a throw inside the service: on C a rejection awaited
// through a function value is lost (compiler card 2026-10-08-await-through-a-function-field-drops-the-rejection-on-c.md).
export interface PermissionReply {
	status: string;
	canAskAgain: boolean;
	error: string;
}

export interface LocationRequest {
	highAccuracy: boolean;
	timeout: number;
	maximumAge: number;
	distanceFilter: number;
	interval: number;
}

// NaN marks an absent altitude, accuracy, heading or speed; `code` is 0 for a fix, else the
// W3C error code (1 permission denied, 2 position unavailable, 3 timeout).
export interface LocationFix {
	code: int32;
	message: string;
	latitude: number;
	longitude: number;
	altitude: number;
	accuracy: number;
	altitudeAccuracy: number;
	heading: number;
	speed: number;
	timestamp: number;
}

export interface DeviceSnapshot {
	brand: string;
	manufacturer: string;
	model: string;
	deviceId: string;
	systemName: string;
	systemVersion: string;
	applicationName: string;
	bundleId: string;
	version: string;
	buildNumber: string;
	isEmulator: boolean;
	isTablet: boolean;
}

export interface BatterySnapshot {
	level: number;
	charging: boolean;
}

// "" marks a field the platform does not report.
export interface LocaleFields {
	languageTag: string;
	languageCode: string;
	scriptCode: string;
	regionCode: string;
	textDirection: string;
	decimalSeparator: string;
	groupingSeparator: string;
	measurementSystem: string;
	currencyCode: string;
	currencySymbol: string;
	temperatureUnit: string;
}

export interface LocaleSnapshot {
	locales: LocaleFields[];
	calendar: string;
	timeZone: string;
	uses24hourClock: boolean;
	firstWeekday: int32;
}

// A notification to schedule; -1 marks no badge, no delay and no date.
export interface NotificationSpec {
	identifier: string;
	title: string;
	subtitle: string;
	body: string;
	data: string;
	sound: boolean;
	badge: number;
	seconds: number;
	repeats: boolean;
	date: number;
}

export interface ScheduleReply {
	identifier: string;
	error: string;
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
	storageGet: (key: string) => string | null;
	storageSet: (key: string, value: string) => void;
	storageRemove: (key: string) => void;
	storageClear: () => void;
	storageKeys: () => string[];
	watchNetInfo: () => void;
	refreshNetInfo: () => void;
	permissionStatus: (name: string) => Promise<PermissionReply>;
	requestPermission: (name: string) => Promise<PermissionReply>;
	androidPermissionGranted: (permission: string) => Promise<boolean>;
	androidShouldShowRationale: (permission: string) => Promise<boolean>;
	androidRequestPermissions: (permissions: string[]) => Promise<PermissionReply[]>;
	locationCurrent: (request: LocationRequest, done: (fix: LocationFix) => void) => void;
	locationWatch: (id: int32, request: LocationRequest, update: (fix: LocationFix) => void) => void;
	locationClear: (id: int32) => void;
	haptic: (kind: string, style: string) => void;
	deviceInfo: () => DeviceSnapshot;
	battery: () => Promise<BatterySnapshot>;
	localization: () => LocaleSnapshot;
	scheduleNotification: (spec: NotificationSpec) => Promise<ScheduleReply>;
	cancelNotification: (identifier: string) => void;
	cancelAllNotifications: () => void;
	dismissAllNotifications: () => void;
	presentNotifications: (decide: boolean) => void;
	presentNotification: (identifier: string, banner: boolean, sound: boolean, badge: boolean) => void;
	lastNotificationResponse: () => Promise<string>;
}

let installed: AppServices | null = null;
let generation: int32 = 0;

export function installAppServices(services: AppServices | null): void {
	installed = services;
	generation += 1;
}

export function appServicesGeneration(): int32 {
	return generation;
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
