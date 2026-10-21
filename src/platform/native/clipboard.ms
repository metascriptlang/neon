import { ClipboardServices, installClipboardServices } from "../../api/clipboardServices";
import { appCall } from "./appBridge";
import { niClipboardCommand } from "./commands.h";

import "../android/library";

when (ios) {
	@compile("../ios/clipboard.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
} else when (android) {
	@compile("../android/app.c");
}

when (ios || android) {
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
