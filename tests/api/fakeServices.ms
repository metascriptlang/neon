import {
	AppServices, AlertRequest, BatterySnapshot, DeviceSnapshot, LocaleSnapshot, LocationFix, LocationRequest,
	NotificationSpec, PermissionReply, ScheduleReply, ShareRequest, installAppServices,
} from "../../src/api/services";
import { NetInfoState, publishNetInfo } from "../../src/api/netInfo";

export class FakeServices {
	log: string[] = [];
	alerts: AlertRequest[] = [];
	shares: ShareRequest[] = [];
	clipboard: string = "";
	openable: boolean = true;
	initial: string = "";
	screenReader: boolean = false;
	images: string[] = [];
	imageDone: ((width: number, height: number, error: string) => void)[] = [];
	storedKeys: string[] = [];
	storedValues: string[] = [];
	permissionNames: string[] = [];
	permissionStates: string[] = [];
	answer: string = "granted";
	rationale: boolean = false;
	currentRequests: LocationRequest[] = [];
	currentDone: ((fix: LocationFix) => void)[] = [];
	watchIds: int32[] = [];
	watchUpdates: ((fix: LocationFix) => void)[] = [];
	watchRequests: LocationRequest[] = [];
	device: DeviceSnapshot = {
		brand: "Apple",
		manufacturer: "Apple",
		model: "iPhone",
		deviceId: "iPhone17,1",
		systemName: "iOS",
		systemVersion: "26.0",
		applicationName: "Neon",
		bundleId: "dev.neon.Fake",
		version: "1.2.0",
		buildNumber: "42",
		isEmulator: true,
		isTablet: false,
	};
	locales: LocaleSnapshot = {
		locales: [
			{
				languageTag: "vi-VN",
				languageCode: "vi",
				scriptCode: "",
				regionCode: "VN",
				textDirection: "ltr",
				decimalSeparator: ",",
				groupingSeparator: ".",
				measurementSystem: "metric",
				currencyCode: "VND",
				currencySymbol: "₫",
				temperatureUnit: "celsius",
			},
			{
				languageTag: "ar-EG",
				languageCode: "ar",
				scriptCode: "",
				regionCode: "EG",
				textDirection: "rtl",
				decimalSeparator: "٫",
				groupingSeparator: "٬",
				measurementSystem: "metric",
				currencyCode: "EGP",
				currencySymbol: "E£",
				temperatureUnit: "celsius",
			},
		],
		calendar: "gregory",
		timeZone: "Asia/Ho_Chi_Minh",
		uses24hourClock: true,
		firstWeekday: 2,
	};
	notifications: NotificationSpec[] = [];
	lastResponse: string = "";
	network: NetInfoState = { type: "wifi", isConnected: true, isInternetReachable: true, details: { isConnectionExpensive: false } };

	install(): void {
		const services: AppServices = {
			dismissKeyboard: (): void => { this.log.push("dismissKeyboard"); },
			alert: (request: AlertRequest): void => {
				this.log.push("alert " + request.title);
				this.alerts.push(request);
			},
			openURL: async (url: string): Promise<boolean> => {
				this.log.push("openURL " + url);
				return this.openable;
			},
			canOpenURL: async (url: string): Promise<boolean> => {
				this.log.push("canOpenURL " + url);
				return this.openable;
			},
			initialURL: async (): Promise<string> => { return this.initial; },
			openSettings: async (): Promise<boolean> => {
				this.log.push("openSettings");
				return true;
			},
			share: (request: ShareRequest): void => {
				this.log.push("share " + request.title + "|" + request.message + "|" + request.url);
				this.shares.push(request);
			},
			vibrate: (pattern: int32[], repeat: boolean): void => {
				let text = "vibrate";
				for (const step of pattern) { text += " " + step.toString(); }
				this.log.push(text + (repeat ? " repeat" : ""));
			},
			cancelVibration: (): void => { this.log.push("cancelVibration"); },
			getClipboard: async (): Promise<string> => { return this.clipboard; },
			setClipboard: (text: string): void => {
				this.log.push("setClipboard " + text);
				this.clipboard = text;
			},
			screenReaderEnabled: async (): Promise<boolean> => { return this.screenReader; },
			reduceMotionEnabled: async (): Promise<boolean> => { return false; },
			announce: (text: string): void => { this.log.push("announce " + text); },
			exitApp: (): void => { this.log.push("exitApp"); },
			imageSize: (uri: string, done: (width: number, height: number, error: string) => void): void => {
				this.log.push("imageSize " + uri);
				this.images.push(uri);
				this.imageDone.push(done);
			},
			storageGet: (key: string): string | null => {
				const at = this.storedKeys.indexOf(key);
				return at < 0 ? null : this.storedValues[at];
			},
			storageSet: (key: string, value: string): void => {
				const at = this.storedKeys.indexOf(key);
				if (at < 0) {
					this.storedKeys.push(key);
					this.storedValues.push(value);
				} else {
					this.storedValues[at] = value;
				}
			},
			storageRemove: (key: string): void => {
				const at = this.storedKeys.indexOf(key);
				if (at >= 0) {
					this.storedKeys.splice(at, 1);
					this.storedValues.splice(at, 1);
				}
			},
			storageClear: (): void => {
				this.storedKeys = [];
				this.storedValues = [];
			},
			storageKeys: (): string[] => { return this.storedKeys.slice(0, this.storedKeys.length); },
			watchNetInfo: (): void => {
				this.log.push("watchNetInfo");
				publishNetInfo(this.network);
			},
			refreshNetInfo: (): void => {
				this.log.push("refreshNetInfo");
				publishNetInfo(this.network);
			},
			permissionStatus: async (name: string): Promise<PermissionReply> => {
				return this.permission(name);
			},
			requestPermission: async (name: string): Promise<PermissionReply> => {
				this.log.push("requestPermission " + name);
				if (this.permission(name).status === "undetermined") { this.setPermission(name, this.answer); }
				return this.permission(name);
			},
			androidPermissionGranted: async (permission: string): Promise<boolean> => {
				return this.permission(permission).status === "granted";
			},
			androidShouldShowRationale: async (permission: string): Promise<boolean> => { return this.rationale; },
			locationCurrent: (request: LocationRequest, done: (fix: LocationFix) => void): void => {
				this.currentRequests.push(request);
				this.currentDone.push(done);
			},
			locationWatch: (id: int32, request: LocationRequest, update: (fix: LocationFix) => void): void => {
				this.log.push("locationWatch " + id.toString());
				this.watchIds.push(id);
				this.watchRequests.push(request);
				this.watchUpdates.push(update);
			},
			locationClear: (id: int32): void => { this.log.push("locationClear " + id.toString()); },
			haptic: (kind: string, style: string): void => { this.log.push("haptic " + kind + " " + style); },
			deviceInfo: (): DeviceSnapshot => { return this.device; },
			battery: async (): Promise<BatterySnapshot> => { return { level: 0.75, charging: true }; },
			localization: (): LocaleSnapshot => { return this.locales; },
			scheduleNotification: async (spec: NotificationSpec): Promise<ScheduleReply> => {
				this.notifications.push(spec);
				return { identifier: spec.identifier, error: spec.title === "refuse" ? "refused by the fake" : "" };
			},
			cancelNotification: (identifier: string): void => { this.log.push("cancelNotification " + identifier); },
			cancelAllNotifications: (): void => { this.log.push("cancelAllNotifications"); },
			dismissAllNotifications: (): void => { this.log.push("dismissAllNotifications"); },
			presentNotifications: (decide: boolean): void => { this.log.push("presentNotifications " + (decide ? "yes" : "no")); },
			presentNotification: (identifier: string, banner: boolean, sound: boolean, badge: boolean): void => {
				this.log.push("presentNotification " + identifier + " " + (banner ? "banner" : "-") + " " + (sound ? "sound" : "-"));
			},
			lastNotificationResponse: async (): Promise<string> => { return this.lastResponse; },
			androidRequestPermissions: async (permissions: string[]): Promise<PermissionReply[]> => {
				this.log.push("androidRequestPermissions " + permissions.join(","));
				const results: PermissionReply[] = [];
				for (const permission of permissions) {
					if (this.permission(permission).status !== "granted") { this.setPermission(permission, this.answer); }
					results.push(this.permission(permission));
				}
				return results;
			},
		};
		installAppServices(services);
	}

	permission(name: string): PermissionReply {
		const at = this.permissionNames.indexOf(name);
		const status = at < 0 ? "undetermined" : this.permissionStates[at];
		return { status, canAskAgain: status === "undetermined", error: "" };
	}

	setPermission(name: string, status: string): void {
		const at = this.permissionNames.indexOf(name);
		if (at < 0) {
			this.permissionNames.push(name);
			this.permissionStates.push(status);
		} else {
			this.permissionStates[at] = status;
		}
	}

	joined(): string {
		return this.log.join(";");
	}
}
