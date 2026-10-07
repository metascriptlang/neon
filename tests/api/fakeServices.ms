import { AppServices, AlertRequest, ShareRequest, installAppServices } from "../../src/api/services";
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
		};
		installAppServices(services);
	}

	joined(): string {
		return this.log.join(";");
	}
}
