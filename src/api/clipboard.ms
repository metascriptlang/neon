import { appServices } from "./services";

export class Clipboard {
	static async getString(): Promise<string> {
		return await appServices("Clipboard.getString").getClipboard();
	}

	static setString(content: string): void {
		appServices("Clipboard.setString").setClipboard(content);
	}

	static async hasString(): Promise<boolean> {
		const text = await appServices("Clipboard.hasString").getClipboard();
		return text !== "";
	}
}
