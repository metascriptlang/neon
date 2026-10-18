import { ClipboardServices, installClipboardServices } from "../../api/clipboardServices";
import { readClipboardText, writeClipboardText } from "../../../../ion/src/clipboard";

export const ionClipboardServices: ClipboardServices = {
	getClipboard: async (): Promise<string> => { return readClipboardText(); },
	setClipboard: (text: string): void => {
		if (!writeClipboardText(text)) { throw new Error("Clipboard.setString: the OS refused the clipboard write"); }
	},
};

installClipboardServices(ionClipboardServices);
