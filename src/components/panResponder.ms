// RN Libraries/Interaction/PanResponder.js over Neon's responder system, one touch.

import { NeonEvent } from "../render/event";
import { touchHistory } from "../render/responder";

export class PanResponderGestureState {
	stateID: number = 0;
	moveX: number = 0;
	moveY: number = 0;
	x0: number = 0;
	y0: number = 0;
	dx: number = 0;
	dy: number = 0;
	vx: number = 0;
	vy: number = 0;
	numberActiveTouches: int32 = 0;
	accountsForMovesUpTo: number = 0;
}

type ActiveCallback = (e: NeonEvent, gestureState: PanResponderGestureState) => boolean;
type PassiveCallback = (e: NeonEvent, gestureState: PanResponderGestureState) => void;

export interface PanResponderCallbacks {
	onMoveShouldSetPanResponder?: ActiveCallback | null;
	onMoveShouldSetPanResponderCapture?: ActiveCallback | null;
	onStartShouldSetPanResponder?: ActiveCallback | null;
	onStartShouldSetPanResponderCapture?: ActiveCallback | null;
	onPanResponderGrant?: PassiveCallback | null;
	onPanResponderReject?: PassiveCallback | null;
	onPanResponderStart?: PassiveCallback | null;
	onPanResponderEnd?: PassiveCallback | null;
	onPanResponderRelease?: PassiveCallback | null;
	onPanResponderMove?: PassiveCallback | null;
	onPanResponderTerminate?: PassiveCallback | null;
	onPanResponderTerminationRequest?: ActiveCallback | null;
	onShouldBlockNativeResponder?: ActiveCallback | null;
}

export interface GestureResponderHandlers {
	onStartShouldSetResponder: (e: NeonEvent) => boolean;
	onStartShouldSetResponderCapture: (e: NeonEvent) => boolean;
	onMoveShouldSetResponder: (e: NeonEvent) => boolean;
	onMoveShouldSetResponderCapture: (e: NeonEvent) => boolean;
	onResponderGrant: (e: NeonEvent) => boolean;
	onResponderReject: (e: NeonEvent) => void;
	onResponderStart: (e: NeonEvent) => void;
	onResponderMove: (e: NeonEvent) => void;
	onResponderEnd: (e: NeonEvent) => void;
	onResponderRelease: (e: NeonEvent) => void;
	onResponderTerminate: (e: NeonEvent) => void;
	onResponderTerminationRequest: (e: NeonEvent) => boolean;
}

export interface PanResponderInstance {
	panHandlers: GestureResponderHandlers;
	getInteractionHandle: () => number | null;
}

export interface PanResponderStatic {
	create: (config: PanResponderCallbacks) => PanResponderInstance;
}

function initializeGestureState(g: PanResponderGestureState): void {
	g.moveX = 0;
	g.moveY = 0;
	g.x0 = 0;
	g.y0 = 0;
	g.dx = 0;
	g.dy = 0;
	g.vx = 0;
	g.vy = 0;
	g.numberActiveTouches = 0;
	g.accountsForMovesUpTo = 0;
}

function updateGestureStateOnMove(g: PanResponderGestureState): void {
	const history = touchHistory();
	g.numberActiveTouches = history.numberActiveTouches;
	const moved = history.currentTimeStamp > g.accountsForMovesUpTo;
	const x = history.currentX;
	const y = history.currentY;
	const previousX = moved ? history.previousX : x;
	const previousY = moved ? history.previousY : y;
	g.moveX = x;
	g.moveY = y;
	const nextDX = g.dx + (x - previousX);
	const nextDY = g.dy + (y - previousY);
	const dt = history.mostRecentTimeStamp - g.accountsForMovesUpTo;
	g.vx = dt > 0 ? (nextDX - g.dx) / dt : 0;
	g.vy = dt > 0 ? (nextDY - g.dy) / dt : 0;
	g.dx = nextDX;
	g.dy = nextDY;
	g.accountsForMovesUpTo = history.mostRecentTimeStamp;
}

function active(callback: ActiveCallback | null, e: NeonEvent, g: PanResponderGestureState): boolean {
	if (callback === null) { return false; }
	return (callback as ActiveCallback)(e, g);
}

function passive(callback: PassiveCallback | null, e: NeonEvent, g: PanResponderGestureState): void {
	if (callback !== null) { (callback as PassiveCallback)(e, g); }
}

let nextStateID = 1;

function create(config: PanResponderCallbacks): PanResponderInstance {
	const g = new PanResponderGestureState();
	g.stateID = nextStateID;
	nextStateID += 1;
	const panHandlers: GestureResponderHandlers = {
		onStartShouldSetResponder: (e: NeonEvent): boolean => active(config.onStartShouldSetPanResponder, e, g),
		onMoveShouldSetResponder: (e: NeonEvent): boolean => active(config.onMoveShouldSetPanResponder, e, g),
		onStartShouldSetResponderCapture: (e: NeonEvent): boolean => {
			initializeGestureState(g);
			g.numberActiveTouches = touchHistory().numberActiveTouches;
			return active(config.onStartShouldSetPanResponderCapture, e, g);
		},
		onMoveShouldSetResponderCapture: (e: NeonEvent): boolean => {
			if (g.accountsForMovesUpTo === touchHistory().mostRecentTimeStamp) { return false; }
			updateGestureStateOnMove(g);
			return active(config.onMoveShouldSetPanResponderCapture, e, g);
		},
		onResponderGrant: (e: NeonEvent): boolean => {
			const history = touchHistory();
			g.x0 = history.currentX;
			g.y0 = history.currentY;
			g.dx = 0;
			g.dy = 0;
			passive(config.onPanResponderGrant, e, g);
			const block = config.onShouldBlockNativeResponder;
			return block === null ? true : (block as ActiveCallback)(e, g);
		},
		onResponderReject: (e: NeonEvent): void => { passive(config.onPanResponderReject, e, g); },
		onResponderRelease: (e: NeonEvent): void => {
			passive(config.onPanResponderRelease, e, g);
			initializeGestureState(g);
		},
		onResponderStart: (e: NeonEvent): void => {
			g.numberActiveTouches = touchHistory().numberActiveTouches;
			passive(config.onPanResponderStart, e, g);
		},
		onResponderMove: (e: NeonEvent): void => {
			if (g.accountsForMovesUpTo === touchHistory().mostRecentTimeStamp) { return; }
			updateGestureStateOnMove(g);
			passive(config.onPanResponderMove, e, g);
		},
		onResponderEnd: (e: NeonEvent): void => {
			g.numberActiveTouches = touchHistory().numberActiveTouches;
			passive(config.onPanResponderEnd, e, g);
		},
		onResponderTerminate: (e: NeonEvent): void => {
			passive(config.onPanResponderTerminate, e, g);
			initializeGestureState(g);
		},
		onResponderTerminationRequest: (e: NeonEvent): boolean => {
			const request = config.onPanResponderTerminationRequest;
			return request === null ? true : (request as ActiveCallback)(e, g);
		},
	};
	return { panHandlers, getInteractionHandle: (): number | null => null };
}

export const PanResponder: PanResponderStatic = { create };
