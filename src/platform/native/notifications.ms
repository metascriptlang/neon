import {
	NotificationServices, NotificationSpec, ScheduleReply, installNotificationServices, notificationEvent,
} from "../../api/notificationServices";
import {
	AppEvent, FIELD, ask, flagText, onNativeAppEvent, onNativeAppStart, refusal,
} from "./appBridge";
import { niNotificationCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/notifications.m", "-fobjc-arc");
	@passL("-framework UserNotifications");
} else when (android) {
	androidLibrary("../android/notifications");
}

function command(name: string, arg: string): string {
	const reply: string = niNotificationCommand(name, arg);
	return reply;
}

async function scheduleNotification(spec: NotificationSpec): Promise<ScheduleReply> {
	const reply = await ask(command, "notification.schedule", [
		spec.identifier, spec.title, spec.subtitle, spec.body, spec.data, flagText(spec.sound), spec.badge.toString(),
		spec.seconds.toString(), flagText(spec.repeats), spec.date.toString(),
	].join(FIELD));
	const error = refusal(reply);
	return { identifier: error === "" ? reply : "", error };
}

export const nativeNotificationServices: NotificationServices = {
	scheduleNotification,
	cancelNotification: (identifier: string): void => { command("notification.cancel", identifier); },
	cancelAllNotifications: (): void => { command("notification.cancelAll", ""); },
	dismissAllNotifications: (): void => { command("notification.dismissAll", ""); },
	presentNotifications: (decide: boolean): void => { command("notification.handler", flagText(decide)); },
	presentNotification: (identifier: string, banner: boolean, sound: boolean, badge: boolean): void => {
		command("notification.present", [identifier, flagText(banner), flagText(sound), flagText(badge)].join(FIELD));
	},
	lastNotificationResponse: async (): Promise<string> => { return command("notification.last", ""); },
};

installNotificationServices(nativeNotificationServices);
onNativeAppEvent(AppEvent.Notification, notificationEvent);
onNativeAppStart((): void => { command("notification.install", ""); });
