import { EventSubscription, Listeners } from "./subscription";
import { NotificationSpec, ScheduleReply, appServices } from "./services";
import { Permissions, PermissionResponse } from "./permissions";

export const DEFAULT_ACTION_IDENTIFIER = "expo.modules.notifications.actions.DEFAULT";

export interface NotificationContentInput {
	title?: string | null;
	subtitle?: string | null;
	body?: string | null;
	data?: string | null;
	sound?: boolean | null;
	badge?: number | null;
}

export interface NotificationTriggerInput {
	seconds?: number | null;
	repeats?: boolean | null;
	date?: number | null;
}

export interface NotificationRequestInput {
	identifier?: string | null;
	content: NotificationContentInput;
	trigger: NotificationTriggerInput | null;
}

export interface NotificationContent {
	title: string | null;
	subtitle: string | null;
	body: string | null;
	data: string;
}

export interface NotificationRequest {
	identifier: string;
	content: NotificationContent;
}

export interface Notification {
	date: number;
	request: NotificationRequest;
}

export interface NotificationResponse {
	notification: Notification;
	actionIdentifier: string;
}

export interface NotificationBehavior {
	shouldShowBanner: boolean;
	shouldShowList: boolean;
	shouldPlaySound: boolean;
	shouldSetBadge: boolean;
}

export interface NotificationHandler {
	handleNotification: (notification: Notification) => Promise<NotificationBehavior>;
}

const FIELD = "\u001f";

const received = new Listeners<Notification>();
const responses = new Listeners<NotificationResponse>();
let handler: NotificationHandler | null = null;
let nextIdentifier: int32 = 1;

function text(value: string | null): string {
	return typeof value === "string" ? value as string : "";
}

function finiteOr(value: number | null, fallback: number): number {
	if (value === null) { return fallback; }
	const given = value as number;
	return Number.isFinite(given) ? given : fallback;
}

function spec(request: NotificationRequestInput): NotificationSpec {
	const content = request.content;
	const trigger = request.trigger;
	const given = text(request.identifier ?? null);
	const identifier = given !== "" ? given : "neon-" + Date.now().toString() + "-" + nextIdentifier.toString();
	nextIdentifier += 1;
	const seconds = trigger === null ? -1 : finiteOr(trigger.seconds ?? null, -1);
	const date = trigger === null ? -1 : finiteOr(trigger.date ?? null, -1);
	const repeats = trigger !== null && trigger.repeats === true;
	if (repeats && seconds < 60) {
		throw new Error("Notifications.scheduleNotificationAsync: a repeating trigger needs at least 60 seconds");
	}
	return {
		identifier,
		title: text(content.title ?? null),
		subtitle: text(content.subtitle ?? null),
		body: text(content.body ?? null),
		data: text(content.data ?? null),
		sound: content.sound === true,
		badge: finiteOr(content.badge ?? null, -1),
		seconds,
		repeats,
		date,
	};
}

function given(value: string): string | null {
	return value === "" ? null : value;
}

export function decodeNotification(fields: string[]): Notification {
	if (fields.length < 7) { throw new Error("Notifications: the host sent a malformed notification: " + fields.join(",")); }
	return {
		date: parseFloat(fields[6]),
		request: {
			identifier: fields[1],
			content: { title: given(fields[2]), subtitle: given(fields[3]), body: given(fields[4]), data: fields[5] },
		},
	};
}

async function present(notification: Notification): Promise<void> {
	const decide = handler;
	if (decide === null) { return; }
	const behavior = await decide.handleNotification(notification);
	appServices("Notifications.setNotificationHandler").presentNotification(
		notification.request.identifier,
		behavior.shouldShowBanner || behavior.shouldShowList,
		behavior.shouldPlaySound,
		behavior.shouldSetBadge,
	);
}

export function publishNotificationEvent(value: string): void {
	const fields = value.split(FIELD);
	const notification = decodeNotification(fields);
	if (fields[0] === "received") {
		present(notification);
		received.emit(notification);
		return;
	}
	responses.emit({ notification, actionIdentifier: fields.length > 7 ? fields[7] : DEFAULT_ACTION_IDENTIFIER });
}

export class Notifications {
	static async getPermissionsAsync(): Promise<PermissionResponse> {
		return await Permissions.check("notifications");
	}

	static async requestPermissionsAsync(): Promise<PermissionResponse> {
		return await Permissions.request("notifications");
	}

	static async scheduleNotificationAsync(request: NotificationRequestInput): Promise<string> {
		const services = appServices("Notifications.scheduleNotificationAsync");
		const reply: ScheduleReply = await services.scheduleNotification(spec(request));
		if (reply.error !== "") { throw new Error(reply.error); }
		return reply.identifier;
	}

	static async cancelScheduledNotificationAsync(identifier: string): Promise<void> {
		appServices("Notifications.cancelScheduledNotificationAsync").cancelNotification(identifier);
	}

	static async cancelAllScheduledNotificationsAsync(): Promise<void> {
		appServices("Notifications.cancelAllScheduledNotificationsAsync").cancelAllNotifications();
	}

	static async dismissAllNotificationsAsync(): Promise<void> {
		appServices("Notifications.dismissAllNotificationsAsync").dismissAllNotifications();
	}

	static setNotificationHandler(next: NotificationHandler | null): void {
		handler = next;
		appServices("Notifications.setNotificationHandler").presentNotifications(next !== null);
	}

	static addNotificationReceivedListener(listener: (notification: Notification) => void): EventSubscription {
		return received.add(listener);
	}

	static addNotificationResponseReceivedListener(listener: (response: NotificationResponse) => void): EventSubscription {
		return responses.add(listener);
	}

	static async getLastNotificationResponseAsync(): Promise<NotificationResponse | null> {
		const last = await appServices("Notifications.getLastNotificationResponseAsync").lastNotificationResponse();
		// A typed const: a bare `return null` is refused here (compiler card 2026-10-08-async-return-null-literal-refused.md).
		const none: NotificationResponse | null = null;
		if (last === "") { return none; }
		const fields = last.split(FIELD);
		const response: NotificationResponse = {
			notification: decodeNotification(fields),
			actionIdentifier: fields.length > 7 ? fields[7] : DEFAULT_ACTION_IDENTIFIER,
		};
		return response;
	}
}
