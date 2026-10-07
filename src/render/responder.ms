// RN ResponderEventPlugin over one touch. Hosts deliver touch events deepest first;
// only the first delivery of a native event negotiates, so ancestors see it once.

import { NeonEvent } from "./event";
import { Host, HostNode } from "./hostTypes";
import { createContext, useContext, Context } from "./context";

export interface ResponderHandlers {
	onStartShouldSetResponder: ((e: NeonEvent) => boolean) | null;
	onStartShouldSetResponderCapture: ((e: NeonEvent) => boolean) | null;
	onMoveShouldSetResponder: ((e: NeonEvent) => boolean) | null;
	onMoveShouldSetResponderCapture: ((e: NeonEvent) => boolean) | null;
	onResponderGrant: ((e: NeonEvent) => boolean) | null;
	onResponderReject: ((e: NeonEvent) => void) | null;
	onResponderStart: ((e: NeonEvent) => void) | null;
	onResponderMove: ((e: NeonEvent) => void) | null;
	onResponderEnd: ((e: NeonEvent) => void) | null;
	onResponderRelease: ((e: NeonEvent) => void) | null;
	onResponderTerminate: ((e: NeonEvent) => void) | null;
	onResponderTerminationRequest: ((e: NeonEvent) => boolean) | null;
}

export enum TouchPhase {
	Start,
	Move,
	End,
	Cancel,
}

export class ResponderEntry {
	handlers: ResponderHandlers;
	parent: ResponderEntry | null;
	host: Host | null = null;
	node: HostNode | null = null;
	mounted: boolean = true;

	constructor(handlers: ResponderHandlers, parent: ResponderEntry | null) {
		this.handlers = handlers;
		this.parent = parent;
	}
}

export class TouchHistory {
	numberActiveTouches: int32 = 0;
	startX: number = 0;
	startY: number = 0;
	startTimeStamp: number = 0;
	previousX: number = 0;
	previousY: number = 0;
	previousTimeStamp: number = 0;
	currentX: number = 0;
	currentY: number = 0;
	currentTimeStamp: number = 0;
	mostRecentTimeStamp: number = 0;
}

export class ClaimWatch {
	onClaim: () => void;
	pressing: boolean = false;

	constructor(onClaim: () => void) {
		this.onClaim = onClaim;
	}
}

const NO_ENTRY: ResponderEntry | null = null;
export const ResponderParent: Context<ResponderEntry | null> = createContext<ResponderEntry | null>(NO_ENTRY);

const history = new TouchHistory();
let responder: ResponderEntry | null = null;
let path: ResponderEntry[] = [];
let active = false;
let lastPhase: int32 = -1;
let lastTime: number = -1;
let lastX: number = 0;
let lastY: number = 0;
let claimedThisTouch = false;
let claimedReleaseTime: number = -1;
const claimWatchers: ClaimWatch[] = [];


export function touchHistory(): TouchHistory {
	return history;
}

export function currentResponder(): ResponderEntry | null {
	return responder;
}

export function parentResponder(): ResponderEntry | null {
	return useContext<ResponderEntry | null>(ResponderParent);
}

// Hosts stamp a press with the timestamp of the release that ended its touch.
export function pressSwallowed(e: NeonEvent): boolean {
	if (claimedThisTouch && active) { return true; }
	return claimedReleaseTime >= 0 && e.timeStamp === claimedReleaseTime;
}

export function watchTouchClaim(watch: ClaimWatch): void {
	watch.pressing = true;
	if (claimWatchers.indexOf(watch) < 0) { claimWatchers.push(watch); }
}

export function unwatchTouchClaim(watch: ClaimWatch): void {
	watch.pressing = false;
	const at = claimWatchers.indexOf(watch);
	if (at >= 0) { claimWatchers.splice(at, 1); }
}

function pathFrom(entry: ResponderEntry): ResponderEntry[] {
	const out: ResponderEntry[] = [];
	let at: ResponderEntry | null = entry;
	while (at !== null) {
		const e = at as ResponderEntry;
		if (e.mounted) { out.push(e); }
		at = e.parent;
	}
	return out;
}

function above(entry: ResponderEntry): ResponderEntry[] {
	const at = path.indexOf(entry);
	if (at < 0) { return path; }
	return path.slice(at + 1, path.length);
}

function ask(handler: ((e: NeonEvent) => boolean) | null, e: NeonEvent): boolean {
	if (handler === null) { return false; }
	return (handler as (e: NeonEvent) => boolean)(e);
}

function tell(handler: ((e: NeonEvent) => void) | null, e: NeonEvent): void {
	if (handler !== null) { (handler as (e: NeonEvent) => void)(e); }
}

function release(entry: ResponderEntry): void {
	const host = entry.host;
	if (host === null) { return; }
	const write = (host as Host).setResponder;
	if (write !== null) {
		(write as (node: HostNode | null, block: boolean) => void)(null, false);
	}
}

function grant(entry: ResponderEntry, e: NeonEvent, moving: boolean): void {
	responder = entry;
	const block = ask(entry.handlers.onResponderGrant, e);
	if (moving) {
		claimedThisTouch = true;
		const watchers = claimWatchers.slice(0, claimWatchers.length);
		for (const watch of watchers) {
			if (!watch.pressing) { continue; }
			watch.pressing = false;
			watch.onClaim();
		}
	}
	const host = entry.host;
	if (host === null || entry.node === null) { return; }
	const write = (host as Host).setResponder;
	if (write !== null) {
		(write as (node: HostNode | null, block: boolean) => void)(entry.node, block);
	}
}

function capture(entry: ResponderEntry, phase: TouchPhase): ((e: NeonEvent) => boolean) | null {
	return phase === TouchPhase.Start ? entry.handlers.onStartShouldSetResponderCapture : entry.handlers.onMoveShouldSetResponderCapture;
}

function bubble(entry: ResponderEntry, phase: TouchPhase): ((e: NeonEvent) => boolean) | null {
	return phase === TouchPhase.Start ? entry.handlers.onStartShouldSetResponder : entry.handlers.onMoveShouldSetResponder;
}

// RN setResponderAndExtractTransfer.
function negotiate(phase: TouchPhase, e: NeonEvent, candidates: ResponderEntry[]): void {
	let wants: ResponderEntry | null = null;
	for (let i = candidates.length - 1; i >= 0 && wants === null; i -= 1) {
		const entry = candidates[i];
		if (entry !== responder && ask(capture(entry, phase), e)) { wants = entry; }
	}
	for (let i = 0; i < candidates.length && wants === null; i += 1) {
		const entry = candidates[i];
		if (entry !== responder && ask(bubble(entry, phase), e)) { wants = entry; }
	}
	if (wants === null) { return; }
	const next = wants as ResponderEntry;
	const moving = phase === TouchPhase.Move;
	if (responder === null) {
		grant(next, e, moving);
		return;
	}
	const holder = responder as ResponderEntry;
	const request = holder.handlers.onResponderTerminationRequest;
	const allowed = request === null ? true : (request as (e: NeonEvent) => boolean)(e);
	if (!allowed) {
		tell(next.handlers.onResponderReject, e);
		return;
	}
	tell(holder.handlers.onResponderTerminate, e);
	grant(next, e, moving);
}

function sample(e: NeonEvent, start: boolean): void {
	if (start) {
		history.startX = e.x;
		history.startY = e.y;
		history.startTimeStamp = e.timeStamp;
		history.previousX = e.x;
		history.previousY = e.y;
		history.previousTimeStamp = e.timeStamp;
	} else {
		history.previousX = history.currentX;
		history.previousY = history.currentY;
		history.previousTimeStamp = history.currentTimeStamp;
	}
	history.currentX = e.x;
	history.currentY = e.y;
	history.currentTimeStamp = e.timeStamp;
	history.mostRecentTimeStamp = e.timeStamp;
}

function finish(e: NeonEvent, released: boolean): void {
	const holder = responder;
	responder = null;
	active = false;
	history.numberActiveTouches = 0;
	if (claimedThisTouch) { claimedReleaseTime = e.timeStamp; }
	claimedThisTouch = false;
	if (holder === null) { return; }
	const entry = holder as ResponderEntry;
	if (released) {
		tell(entry.handlers.onResponderEnd, e);
		tell(entry.handlers.onResponderRelease, e);
	} else {
		tell(entry.handlers.onResponderTerminate, e);
	}
	release(entry);
}

function repeated(phase: TouchPhase, e: NeonEvent): boolean {
	const code = phase as int32;
	if (code === lastPhase && e.timeStamp === lastTime && e.x === lastX && e.y === lastY) { return true; }
	lastPhase = code;
	lastTime = e.timeStamp;
	lastX = e.x;
	lastY = e.y;
	return false;
}

export function responderTouch(entry: ResponderEntry, phase: TouchPhase, e: NeonEvent): void {
	if (repeated(phase, e)) { return; }
	if (phase !== TouchPhase.Start && !active) { return; }
	match (phase) {
		TouchPhase.Start => { startTouch(entry, e); },
		TouchPhase.Move => { moveTouch(e); },
		TouchPhase.End => {
			sample(e, false);
			finish(e, true);
		},
		TouchPhase.Cancel => { finish(e, false); },
	}
}

function startTouch(entry: ResponderEntry, e: NeonEvent): void {
	if (active) { finish(e, false); }
	active = true;
	claimedThisTouch = false;
	claimedReleaseTime = -1;
	history.numberActiveTouches = 1;
	sample(e, true);
	path = pathFrom(entry);
	negotiate(TouchPhase.Start, e, path);
	const holder = responder;
	if (holder !== null) { tell((holder as ResponderEntry).handlers.onResponderStart, e); }
}

function moveTouch(e: NeonEvent): void {
	sample(e, false);
	const holder = responder;
	negotiate(TouchPhase.Move, e, holder === null ? path : above(holder as ResponderEntry));
	const now = responder;
	if (now !== null) { tell((now as ResponderEntry).handlers.onResponderMove, e); }
}

export function responderUnmounted(entry: ResponderEntry): void {
	entry.mounted = false;
	if (responder !== entry) { return; }
	responder = null;
	const e: NeonEvent = {
		type: "responderterminate", timeStamp: history.mostRecentTimeStamp, value: "",
		x: history.currentX, y: history.currentY, width: 0, height: 0, contentWidth: 0, contentHeight: 0,
		key: "", code: "", altKey: false, ctrlKey: false, metaKey: false, shiftKey: false, repeat: false, isComposing: false,
	};
	tell(entry.handlers.onResponderTerminate, e);
	release(entry);
}
