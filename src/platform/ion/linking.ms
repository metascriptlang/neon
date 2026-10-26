import { LinkingServices, installLinkingServices, urlEvent } from "../../api/linkingServices";
import { openExternal } from "../../../../ion/src/shell";
import { listen } from "../../../../ion/src/ipc";

let initialUrl = "";

export function linkingServicesOver(open: (url: string) => void): LinkingServices {
	return {
		openURL: async (url: string): Promise<boolean> => {
			open(url);
			return true;
		},
		canOpenURL: async (url: string): Promise<boolean> => { return true; },
		initialURL: async (): Promise<string> => { return initialUrl; },
		openSettings: async (): Promise<boolean> => { throw new Error("Linking.openSettings is not available on an Ion desktop host yet"); },
	};
}

export const ionLinkingServices: LinkingServices = linkingServicesOver(openExternal);

export function ionLinkingMessage(name: string, payload: string): void {
	if (name !== "deeplink") { return; }
	if (initialUrl === "") { initialUrl = payload; }
	urlEvent(payload);
}

installLinkingServices(ionLinkingServices);
listen(ionLinkingMessage);
