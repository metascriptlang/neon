import { niAppCall } from "./app.h";

export const FIELD = "\u001f";
export const RECORD = "\u001e";

// The ordinals are the NI_APP_* kinds of app.h.
export enum AppEvent {
	State,
	BackPress,
	Alert,
	ScreenReader,
	Url,
	Share,
	MemoryWarning,
	ReduceMotion,
	ImageSize,
	Reply,
	NetInfo,
	Location,
	Notification,
	Sound,
	Recording,
	ActionSheet,
	Settings,
}

export type AppCommand = (name: string, arg: string) => string;

export function appCall(name: string, arg: string): string {
	const reply: string = niAppCall(name, arg);
	return reply;
}

interface EventHandler {
	kind: AppEvent;
	handle: (value: string) => void;
}

const handlers: EventHandler[] = [];
const starts: (() => void)[] = [];

export function onNativeAppEvent(kind: AppEvent, handle: (value: string) => void): void {
	handlers.push({ kind, handle });
}

export function dispatchNativeAppEvent(kind: AppEvent, value: string): void {
	for (const handler of handlers) {
		if (handler.kind === kind) { handler.handle(value); }
	}
}

export function onNativeAppStart(start: () => void): void {
	starts.push(start);
}

export function runNativeAppStarts(): void {
	for (const start of starts) { start(); }
}

interface PendingReply {
	id: int32;
	done: (reply: string) => void;
}

const replies: PendingReply[] = [];
let nextReply: int32 = 1;

export function requestReply(command: AppCommand, name: string, arg: string, done: (reply: string) => void): void {
	const id = nextReply;
	nextReply += 1;
	const reply = command(name, id.toString() + FIELD + arg);
	if (reply !== "") {
		done(reply);
		return;
	}
	replies.push({ id, done });
}

export async function ask(command: AppCommand, name: string, arg: string): Promise<string> {
	return await new Promise<string>((resolve) => {
		requestReply(command, name, arg, (reply: string): void => { resolve(reply); });
	});
}

function onReplyEvent(value: string): void {
	const split = value.indexOf(FIELD);
	const id = parseInt(split < 0 ? value : value.substring(0, split)) as int32;
	const reply = split < 0 ? "" : value.substring(split + 1, value.length);
	for (let i = 0; i < replies.length; i += 1) {
		if (replies[i].id === id) {
			const pending = replies[i];
			replies.splice(i, 1);
			pending.done(reply);
			return;
		}
	}
}

onNativeAppEvent(AppEvent.Reply, onReplyEvent);

export function refusal(reply: string): string {
	return reply.startsWith("!") ? reply.substring(1, reply.length) : "";
}

export function flagText(value: boolean): string {
	return value ? "1" : "0";
}
