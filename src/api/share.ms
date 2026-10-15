import { appServices } from "./services";

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
		return await new Promise<ShareAction>((resolve) => {
			appServices("Share.share").share({
				title,
				message,
				url,
				done: (action: string, activityType: string): void => {
					resolve({ action, activityType: activityType === "" ? null : activityType });
				},
			});
		});
	}
}
