import { ClipboardServices, installClipboardServices } from "../../api/clipboardServices";
import { appCall } from "./appBridge";
import { niClipboardCommand } from "../ios/commands.h";

when (ios) {
	@compile("../ios/clipboard.m", "-fobjc-arc");

	function command(name: string, arg: string): string {
		const reply: string = niClipboardCommand(name, arg);
		return reply;
	}
} else {
	function command(name: string, arg: string): string {
		return appCall(name, arg);
	}
}

export const nativeClipboardServices: ClipboardServices = {
	getClipboard: async (): Promise<string> => { return command("clipboard.get", ""); },
	setClipboard: (text: string): void => { command("clipboard.set", text); },
};

installClipboardServices(nativeClipboardServices);
