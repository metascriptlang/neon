import { EventSubscription, Listeners } from "./subscription";
import { linkingServices, listenUrls } from "./linkingServices";

when (js && !server) {
	import "../platform/browser/linking";
} else when (ios || android) {
	import "../platform/native/linking";
} else when (macos || windows || linux) {
	import "../platform/ion/linking";
}

export interface LinkingUrlEvent {
	url: string;
}

const urls = new Listeners<LinkingUrlEvent>();

export class Linking {
	static async openURL(url: string): Promise<void> {
		const opened = await linkingServices("Linking.openURL").openURL(url);
		if (!opened) { throw new Error("Unable to open URL: " + url); }
	}

	static async canOpenURL(url: string): Promise<boolean> {
		return await linkingServices("Linking.canOpenURL").canOpenURL(url);
	}

	static async getInitialURL(): Promise<string | null> {
		const url = await linkingServices("Linking.getInitialURL").initialURL();
		return url === "" ? null : url;
	}

	static async openSettings(): Promise<void> {
		const opened = await linkingServices("Linking.openSettings").openSettings();
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

listenUrls(publishUrl);
