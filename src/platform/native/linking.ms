import { LinkingServices, installLinkingServices, urlEvent } from "../../api/linkingServices";
import { AppEvent, onNativeAppEvent } from "./appBridge";
import { niLinkingCommand } from "./commands.h";

when (ios) {
	@compile("../ios/linking.m", "-fobjc-arc");
}

function command(name: string, arg: string): string {
	const reply: string = niLinkingCommand(name, arg);
	return reply;
}

export const nativeLinkingServices: LinkingServices = {
	openURL: async (url: string): Promise<boolean> => { return command("linking.open", url) === "1"; },
	canOpenURL: async (url: string): Promise<boolean> => { return command("linking.canOpen", url) === "1"; },
	initialURL: async (): Promise<string> => { return command("linking.initial", ""); },
	openSettings: async (): Promise<boolean> => { return command("linking.settings", "") === "1"; },
};

installLinkingServices(nativeLinkingServices);
onNativeAppEvent(AppEvent.Url, urlEvent);
