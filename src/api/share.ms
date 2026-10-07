import { appServices } from "./services";
import { sleepAsync } from "std/core/promise";

export interface ShareContent {
	title?: string | null;
	message?: string | null;
	url?: string | null;
}

export interface ShareOptions {
	dialogTitle?: string | null;
	subject?: string | null;
}

export interface ShareAction {
	action: string;
	activityType: string | null;
}

// Polls instead of settling a `new Promise`, which does not lower (compiler card
// 2026-10-07-new-promise-executor-does-not-lower.md); not generic, as an async method of a
// generic class is refused (2026-10-07-async-function-nested-in-generic-function.md).
class ShareSlot {
	settled: boolean = false;
	value: ShareAction = { action: "dismissedAction", activityType: null };

	settle(value: ShareAction): void {
		if (this.settled) { return; }
		this.value = value;
		this.settled = true;
	}

	async wait(): Promise<ShareAction> {
		while (!this.settled) { await sleepAsync(16); }
		return this.value;
	}
}

export class Share {
	static sharedAction: string = "sharedAction";
	static dismissedAction: string = "dismissedAction";

	static async share(content: ShareContent, options: ShareOptions = {}): Promise<ShareAction> {
		const message = content.message ?? "";
		const url = content.url ?? "";
		if (message === "" && url === "") {
			throw new Error("Share.share: at least one of message and url is required");
		}
		const title = options.dialogTitle ?? (content.title ?? "");
		const result = new ShareSlot();
		appServices("Share.share").share({
			title,
			message,
			url,
			done: (action: string, activityType: string): void => {
				result.settle({ action, activityType: activityType === "" ? null : activityType });
			},
		});
		return await result.wait();
	}
}
