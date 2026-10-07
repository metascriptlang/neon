import { EventSubscription, Listeners } from "./subscription";
import { appServices } from "./services";

export interface LinkingUrlEvent {
	url: string;
}

const urls = new Listeners<LinkingUrlEvent>();

// RN's Linking.
export class Linking {
	static async openURL(url: string): Promise<void> {
		const opened = await appServices("Linking.openURL").openURL(url);
		if (!opened) { throw new Error("Unable to open URL: " + url); }
	}

	static async canOpenURL(url: string): Promise<boolean> {
		return await appServices("Linking.canOpenURL").canOpenURL(url);
	}

	// The URL that launched the app, or null; "best effort": Android reads the launch
	// intent's data, iOS and the browser give the page or launch URL they know.
	static async getInitialURL(): Promise<string | null> {
		const url = await appServices("Linking.getInitialURL").initialURL();
		return url === "" ? null : url;
	}

	static async openSettings(): Promise<void> {
		const opened = await appServices("Linking.openSettings").openSettings();
		if (!opened) { throw new Error("Unable to open the app's settings"); }
	}

	static addEventListener(
		type: "url",
		handler: (event: LinkingUrlEvent) => void,
	): EventSubscription {
		return urls.add(handler);
	}
}

export function publishUrl(url: string): void {
	urls.emit({ url });
}
