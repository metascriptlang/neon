import {
	NotificationServices, NotificationSpec, ScheduleReply, installNotificationServices, notificationEvent,
} from "../../api/notificationServices";
import { listen } from "../../../../ion/src/ipc";
import { notify } from "../../../../ion/src/notify";

const FIELD = "\u001f";
const CLICK = "notification.click";

const posted = new Map<string, string[]>();
let lastResponse = "";

function unavailable(api: string): Error {
	return new Error(`${api} is not available on an Ion desktop host yet`);
}

function refused(option: string): ScheduleReply {
	return { identifier: "", error: `Notifications.scheduleNotificationAsync: ${option} is not available on an Ion desktop host yet` };
}

export function ionNotificationServices(post: (title: string, body: string, id: string) => void): NotificationServices {
	return {
		scheduleNotification: async (spec: NotificationSpec): Promise<ScheduleReply> => {
			if (spec.seconds >= 0 || spec.date >= 0 || spec.repeats) { return refused("a trigger"); }
			if (spec.badge >= 0) { return refused("content.badge"); }
			posted.set(spec.identifier, [spec.identifier, spec.title, spec.subtitle, spec.body, spec.data, Date.now().toString()]);
			post(spec.title, spec.body, spec.identifier);
			return { identifier: spec.identifier, error: "" };
		},
		cancelNotification: (identifier: string): void => { throw unavailable("Notifications.cancelScheduledNotificationAsync"); },
		cancelAllNotifications: (): void => { throw unavailable("Notifications.cancelAllScheduledNotificationsAsync"); },
		dismissAllNotifications: (): void => { throw unavailable("Notifications.dismissAllNotificationsAsync"); },
		presentNotifications: (decide: boolean): void => {},
		presentNotification: (identifier: string, banner: boolean, sound: boolean, badge: boolean): void => {},
		lastNotificationResponse: async (): Promise<string> => { return lastResponse; },
	};
}

export function ionNotificationClick(name: string, payload: string): void {
	if (name !== CLICK) { return; }
	const sent = posted.get(payload);
	if (sent === undefined) { return; }
	lastResponse = ["response", ...sent].join(FIELD);
	notificationEvent(lastResponse);
}

installNotificationServices(ionNotificationServices(notify));
listen(ionNotificationClick);
