import { AppServices, AlertRequest, ShareRequest, installAppServices } from "../../src/api/services";

// A host's app services that record every call and answer from fields a test sets.
export class FakeServices {
	log: string[] = [];
	alerts: AlertRequest[] = [];
	shares: ShareRequest[] = [];
	clipboard: string = "";
	openable: boolean = true;
	initial: string = "";
	screenReader: boolean = false;

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
		};
		installAppServices(services);
	}

	joined(): string {
		return this.log.join(";");
	}
}
