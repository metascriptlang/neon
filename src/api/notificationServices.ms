// A notification to schedule; -1 marks no badge, no delay and no date.
export interface NotificationSpec {
	identifier: string;
	title: string;
	subtitle: string;
	body: string;
	data: string;
	sound: boolean;
	badge: number;
	seconds: number;
	repeats: boolean;
	date: number;
}

export interface ScheduleReply {
	identifier: string;
	error: string;
}

export interface NotificationServices {
	scheduleNotification: (spec: NotificationSpec) => Promise<ScheduleReply>;
	cancelNotification: (identifier: string) => void;
	cancelAllNotifications: () => void;
	dismissAllNotifications: () => void;
	presentNotifications: (decide: boolean) => void;
	presentNotification: (identifier: string, banner: boolean, sound: boolean, badge: boolean) => void;
	lastNotificationResponse: () => Promise<string>;
}

let installed: NotificationServices | null = null;
let listener: (value: string) => void = (value: string): void => {};

export function installNotificationServices(services: NotificationServices | null): void {
	installed = services;
}

export function notificationServices(api: string): NotificationServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}

export function listenNotificationEvents(next: (value: string) => void): void {
	listener = next;
}

export function notificationEvent(value: string): void {
	listener(value);
}
