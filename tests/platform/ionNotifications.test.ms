import {
	Notifications, NotificationResponse, DEFAULT_ACTION_IDENTIFIER,
} from "../../src/api/notifications";
import { installNotificationServices } from "../../src/api/notificationServices";
import { ionNotificationServices, ionNotificationClick } from "../../src/platform/ion/notifications";

async function refusal(run: () => Promise<void>): Promise<string> {
	try {
		await run();
	} catch (e) {
		return (e as Error).message;
	}
	return "";
}

test "an immediate notification is posted through Ion and its click arrives as a response" {
	let title = "";
	let body = "";
	let id = "";
	installNotificationServices(ionNotificationServices((t: string, b: string, i: string): void => {
		title = t;
		body = b;
		id = i;
	}));
	let clicked: NotificationResponse | null = null;
	const subscription = Notifications.addNotificationResponseReceivedListener((r: NotificationResponse): void => { clicked = r; });
	const got = await Notifications.scheduleNotificationAsync({
		identifier: "n1",
		content: { title: "Saved", body: "Done", data: "payload" },
		trigger: null,
	});
	assert got === "n1", got;
	assert title === "Saved" && body === "Done" && id === "n1", title + "/" + body + "/" + id;
	ionNotificationClick("other.event", "n1");
	assert clicked === null, "another message is ignored";
	ionNotificationClick("notification.click", "unknown");
	assert clicked === null, "a click on an id this app did not post is ignored";
	ionNotificationClick("notification.click", "n1");
	const response = clicked as NotificationResponse;
	assert response.notification.request.identifier === "n1", response.notification.request.identifier;
	assert response.notification.request.content.title === "Saved", "title";
	assert response.notification.request.content.data === "payload", "data";
	assert response.actionIdentifier === DEFAULT_ACTION_IDENTIFIER, response.actionIdentifier;
	const last = await Notifications.getLastNotificationResponseAsync();
	assert last !== null, "the last response is kept";
	subscription.remove();
}

test "a trigger, a badge, cancel and dismiss are refused by name" {
	installNotificationServices(ionNotificationServices((t: string, b: string, i: string): void => {}));
	let message = await refusal(async (): Promise<void> => {
		await Notifications.scheduleNotificationAsync({ content: { title: "later" }, trigger: { seconds: 5 } });
	});
	assert message === "Notifications.scheduleNotificationAsync: a trigger is not available on an Ion desktop host yet", message;
	message = await refusal(async (): Promise<void> => {
		await Notifications.scheduleNotificationAsync({ content: { title: "b", badge: 3 }, trigger: null });
	});
	assert message === "Notifications.scheduleNotificationAsync: content.badge is not available on an Ion desktop host yet", message;
	message = await refusal(async (): Promise<void> => { await Notifications.cancelAllScheduledNotificationsAsync(); });
	assert message === "Notifications.cancelAllScheduledNotificationsAsync is not available on an Ion desktop host yet", message;
	message = await refusal(async (): Promise<void> => { await Notifications.dismissAllNotificationsAsync(); });
	assert message === "Notifications.dismissAllNotificationsAsync is not available on an Ion desktop host yet", message;
}
