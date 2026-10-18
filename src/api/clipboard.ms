import { clipboardServices } from "./clipboardServices";

when (js && !server) {
	import "../platform/browser/clipboard";
} else when (ios || android) {
	import "../platform/native/clipboard";
} else when (macos || windows || linux) {
	import "../platform/ion/clipboard";
}

export class Clipboard {
	static async getString(): Promise<string> {
		return await clipboardServices("Clipboard.getString").getClipboard();
	}

	static setString(content: string): void {
		clipboardServices("Clipboard.setString").setClipboard(content);
	}

	static async hasString(): Promise<boolean> {
		const text = await clipboardServices("Clipboard.hasString").getClipboard();
		return text !== "";
	}
}
