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
	Accessibility,
	ActionSheet,
	Settings,
}

export const PENDING_REPLY = "";

const LAST_APP_EVENT = AppEvent.Settings as int32;
const INT32_MIN = -2147483648;
const INT32_MAX = 2147483647;

export type AppCommand = (name: string, arg: string) => string;

export function appCall(name: string, arg: string): string {
	return niAppCall(name, arg);
}

export function appEventOf(kind: int32): AppEvent {
	if (kind < 0 || kind > LAST_APP_EVENT) { throw new Error("App bridge: the host sent the unknown event kind " + kind.toString()); }
	return kind as AppEvent;
}

export function wireInt(module: string, field: string, text: string): int32 {
	const value = parseInt(text);
	if (value.toString() !== text || value < INT32_MIN || value > INT32_MAX) {
		throw new Error(module + ": the host sent a malformed " + field + ": " + text);
	}
	return value as int32;
}

export function wireFields(module: string, text: string, minimum: int32): string[] {
	const fields = text.split(FIELD);
	if (fields.length < minimum) { throw new Error(module + ": the host sent " + fields.length.toString() + " fields where " + minimum.toString() + " are needed: " + text); }
	return fields;
}

export function wireId(module: string, value: string): int32 {
	const split = value.indexOf(FIELD);
	return wireInt(module, "request id", split < 0 ? value : value.substring(0, split));
}

export function wirePayload(value: string): string {
	const split = value.indexOf(FIELD);
	return split < 0 ? "" : value.substring(split + 1, value.length);
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
	if (reply !== PENDING_REPLY) {
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
	const id = wireId("App bridge", value);
	for (let i = 0; i < replies.length; i += 1) {
		if (replies[i].id === id) {
			const pending = replies[i];
			replies.splice(i, 1);
			pending.done(wirePayload(value));
			return;
		}
	}
}

onNativeAppEvent(AppEvent.Reply, onReplyEvent);

export function presentValue(reply: string): string | null {
	return reply.startsWith("=") ? reply.substring(1, reply.length) : null;
}

export function refusal(reply: string): string {
	return reply.startsWith("!") ? reply.substring(1, reply.length) : "";
}

export function flagText(value: boolean): string {
	return value ? "1" : "0";
}
