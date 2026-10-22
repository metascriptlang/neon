// RN Pressability (Libraries/Pressability/Pressability.js): each pressable owns
// one touch state machine and takes part in the responder system, so a parent
// that claims the touch terminates the press and onPress never fires.

import { NeonEvent } from "./event";
import { Host, HostNode, MeasureRect, MeasureError } from "./hostTypes";
import { ResponderHandlers } from "./responder";
import { Accessor } from "../core/signal";

export interface PressRect {
	top: number;
	left: number;
	bottom: number;
	right: number;
}

export interface PressabilityConfig {
	cancelable: Accessor<boolean> | null;
	hitSlop: (() => PressRect) | null;
	delayLongPress: Accessor<number> | null;
	onPress: ((e: NeonEvent) => void) | null;
	onPressIn: ((e: NeonEvent) => void) | null;
	onPressOut: ((e: NeonEvent) => void) | null;
	onLongPress: ((e: NeonEvent) => void) | null;
	onHoverIn: ((e: NeonEvent) => void) | null;
	onHoverOut: ((e: NeonEvent) => void) | null;
}

enum TouchState {
	NotResponder,
	InactivePressIn,
	InactivePressOut,
	ActivePressIn,
	ActivePressOut,
	ActiveLongPressIn,
	ActiveLongPressOut,
	Error,
}

enum TouchSignal {
	Delay,
	ResponderGrant,
	ResponderRelease,
	ResponderTerminated,
	EnterPressRect,
	LeavePressRect,
	LongPressDetected,
}

function transition(state: TouchState, signal: TouchSignal): TouchState {
	return match (state) {
		TouchState.NotResponder => signal === TouchSignal.ResponderGrant ? TouchState.InactivePressIn : TouchState.Error,
		TouchState.InactivePressIn => match (signal) {
			TouchSignal.Delay => TouchState.ActivePressIn,
			TouchSignal.ResponderRelease => TouchState.NotResponder,
			TouchSignal.ResponderTerminated => TouchState.NotResponder,
			TouchSignal.EnterPressRect => TouchState.InactivePressIn,
			TouchSignal.LeavePressRect => TouchState.InactivePressOut,
			_ => TouchState.Error,
		},
		TouchState.InactivePressOut => match (signal) {
			TouchSignal.Delay => TouchState.ActivePressOut,
			TouchSignal.ResponderRelease => TouchState.NotResponder,
			TouchSignal.ResponderTerminated => TouchState.NotResponder,
			TouchSignal.EnterPressRect => TouchState.InactivePressIn,
			TouchSignal.LeavePressRect => TouchState.InactivePressOut,
			_ => TouchState.Error,
		},
		TouchState.ActivePressIn => match (signal) {
			TouchSignal.ResponderRelease => TouchState.NotResponder,
			TouchSignal.ResponderTerminated => TouchState.NotResponder,
			TouchSignal.EnterPressRect => TouchState.ActivePressIn,
			TouchSignal.LeavePressRect => TouchState.ActivePressOut,
			TouchSignal.LongPressDetected => TouchState.ActiveLongPressIn,
			_ => TouchState.Error,
		},
		TouchState.ActivePressOut => match (signal) {
			TouchSignal.ResponderRelease => TouchState.NotResponder,
			TouchSignal.ResponderTerminated => TouchState.NotResponder,
			TouchSignal.EnterPressRect => TouchState.ActivePressIn,
			TouchSignal.LeavePressRect => TouchState.ActivePressOut,
			_ => TouchState.Error,
		},
		TouchState.ActiveLongPressIn => match (signal) {
			TouchSignal.ResponderRelease => TouchState.NotResponder,
			TouchSignal.ResponderTerminated => TouchState.NotResponder,
			TouchSignal.EnterPressRect => TouchState.ActiveLongPressIn,
			TouchSignal.LeavePressRect => TouchState.ActiveLongPressOut,
			TouchSignal.LongPressDetected => TouchState.ActiveLongPressIn,
			_ => TouchState.Error,
		},
		TouchState.ActiveLongPressOut => match (signal) {
			TouchSignal.ResponderRelease => TouchState.NotResponder,
			TouchSignal.ResponderTerminated => TouchState.NotResponder,
			TouchSignal.EnterPressRect => TouchState.ActiveLongPressIn,
			TouchSignal.LeavePressRect => TouchState.ActiveLongPressOut,
			_ => TouchState.Error,
		},
		TouchState.Error => match (signal) {
			TouchSignal.ResponderGrant => TouchState.InactivePressIn,
			_ => TouchState.NotResponder,
		},
	};
}

function isActive(state: TouchState): boolean {
	return state === TouchState.ActivePressIn || state === TouchState.ActiveLongPressIn;
}

function isActivation(state: TouchState): boolean {
	return state === TouchState.ActivePressOut || state === TouchState.ActivePressIn;
}

function isPressIn(state: TouchState): boolean {
	return state === TouchState.InactivePressIn || state === TouchState.ActivePressIn || state === TouchState.ActiveLongPressIn;
}

const DEFAULT_LONG_PRESS_DELAY_MS = 500;
const DEFAULT_PRESS_RECT_OFFSETS: PressRect = { top: 20, left: 20, bottom: 30, right: 20 };
const DEFAULT_MIN_PRESS_DURATION = 130;
const LONG_PRESS_DEACTIVATION_DISTANCE = 10;

function tell(handler: ((e: NeonEvent) => void) | null, e: NeonEvent): void {
	if (handler !== null) { (handler as (e: NeonEvent) => void)(e); }
}

export class Pressability {
	private config: PressabilityConfig;
	private host: Host | null = null;
	private node: HostNode | null = null;
	private state: TouchState = TouchState.NotResponder;
	private granted: boolean = false;
	private region: MeasureRect | null = null;
	private activateX: number = 0;
	private activateY: number = 0;
	private activated: boolean = false;
	private activateTime: number = -1;
	private longPressId: int32 = -1;
	private pressOutId: int32 = -1;
	private hovered: boolean = false;

	constructor(config: PressabilityConfig) {
		this.config = config;
	}

	attach(host: Host, node: HostNode): void {
		this.host = host;
		this.node = node;
	}

	reset(): void {
		this.cancelLongPress();
		this.cancelPressOut();
		this.state = TouchState.NotResponder;
		this.granted = false;
	}

	responderHandlers(): ResponderHandlers {
		return {
			onStartShouldSetResponder: (e: NeonEvent): boolean => true,
			onStartShouldSetResponderCapture: null,
			onMoveShouldSetResponder: null,
			onMoveShouldSetResponderCapture: null,
			onResponderGrant: (e: NeonEvent): boolean => { this.grant(e); return false; },
			onResponderReject: null,
			onResponderStart: null,
			onResponderMove: (e: NeonEvent): void => { this.move(e); },
			onResponderEnd: null,
			onResponderRelease: (e: NeonEvent): void => { this.receive(TouchSignal.ResponderRelease, e); },
			onResponderTerminate: (e: NeonEvent): void => { this.receive(TouchSignal.ResponderTerminated, e); },
			onResponderTerminationRequest: (e: NeonEvent): boolean => {
				const cancelable = this.config.cancelable;
				return cancelable === null ? true : (cancelable as Accessor<boolean>)();
			},
		};
	}

	// RN getEventHandlers' W3C pointer hover: onHoverOut answers only a pointer that hovered in.
	pointerEnter(e: NeonEvent): void {
		this.hovered = true;
		tell(this.config.onHoverIn, e);
	}

	pointerLeave(e: NeonEvent): void {
		if (!this.hovered) { return; }
		this.hovered = false;
		tell(this.config.onHoverOut, e);
	}

	// RN onClick: a click that came from a pointer already pressed through the responder.
	click(e: NeonEvent): void {
		if (e.pointerOrigin) { return; }
		tell(this.config.onPress, e);
	}

	private grant(e: NeonEvent): void {
		this.cancelPressOut();
		this.granted = true;
		this.state = TouchState.NotResponder;
		this.receive(TouchSignal.ResponderGrant, e);
		this.receive(TouchSignal.Delay, e);
		const delay = this.config.delayLongPress;
		const wait = delay === null ? DEFAULT_LONG_PRESS_DELAY_MS : Math.max(10, (delay as Accessor<number>)());
		this.longPressId = setTimeout((): void => {
			this.longPressId = -1;
			if (this.state === TouchState.ActivePressIn || this.state === TouchState.ActiveLongPressIn) {
				this.receive(TouchSignal.LongPressDetected, e);
			}
		}, wait) as int32;
	}

	private move(e: NeonEvent): void {
		const region = this.region;
		if (region === null) { return; }
		if (this.activated && Math.hypot(this.activateX - e.x, this.activateY - e.y) > LONG_PRESS_DEACTIVATION_DISTANCE) {
			this.cancelLongPress();
		}
		if (this.within(e, region as MeasureRect)) {
			this.receive(TouchSignal.EnterPressRect, e);
		} else {
			this.cancelLongPress();
			this.receive(TouchSignal.LeavePressRect, e);
		}
	}

	private within(e: NeonEvent, region: MeasureRect): boolean {
		let top = region.y - DEFAULT_PRESS_RECT_OFFSETS.top;
		let left = region.x - DEFAULT_PRESS_RECT_OFFSETS.left;
		let bottom = region.y + region.height + DEFAULT_PRESS_RECT_OFFSETS.bottom;
		let right = region.x + region.width + DEFAULT_PRESS_RECT_OFFSETS.right;
		const slop = this.config.hitSlop;
		if (slop !== null) {
			const s = (slop as () => PressRect)();
			top -= s.top;
			left -= s.left;
			bottom += s.bottom;
			right += s.right;
		}
		return e.x > left && e.x < right && e.y > top && e.y < bottom;
	}

	private receive(signal: TouchSignal, e: NeonEvent): void {
		if (!this.granted && signal === TouchSignal.ResponderRelease) { return; }
		const prev = this.state;
		const next = transition(prev, signal);
		if (next === TouchState.Error) {
			throw new Error(`Pressability: invalid signal ${signal as int32} for state ${prev as int32}`);
		}
		if (prev === next) { return; }
		this.state = next;
		this.sideEffects(prev, next, signal, e);
	}

	private sideEffects(prev: TouchState, next: TouchState, signal: TouchSignal, e: NeonEvent): void {
		const terminal = signal === TouchSignal.ResponderRelease || signal === TouchSignal.ResponderTerminated;
		if (terminal) {
			this.activated = false;
			this.granted = false;
			this.cancelLongPress();
		}
		const initial = prev === TouchState.NotResponder && next === TouchState.InactivePressIn;
		if (initial || (!isActivation(prev) && isActivation(next))) { this.measure(); }
		if (isPressIn(prev) && signal === TouchSignal.LongPressDetected) { tell(this.config.onLongPress, e); }
		const wasActive = isActive(prev);
		const nowActive = isActive(next);
		if (!wasActive && nowActive) { this.activate(e); }
		else if (wasActive && !nowActive) { this.deactivate(e); }
		if (isPressIn(prev) && signal === TouchSignal.ResponderRelease) {
			if (!nowActive && !wasActive) {
				this.activate(e);
				this.deactivate(e);
			}
			const longPressed = this.config.onLongPress !== null && prev === TouchState.ActiveLongPressIn;
			if (!longPressed) { tell(this.config.onPress, e); }
		}
	}

	private activate(e: NeonEvent): void {
		this.activated = true;
		this.activateX = e.x;
		this.activateY = e.y;
		this.activateTime = performance.now();
		tell(this.config.onPressIn, e);
	}

	private deactivate(e: NeonEvent): void {
		const pressOut = this.config.onPressOut;
		if (pressOut !== null) {
			const fire = pressOut as (e: NeonEvent) => void;
			const wait = DEFAULT_MIN_PRESS_DURATION - (performance.now() - this.activateTime);
			if (wait > 0) {
				const held: NeonEvent = { ...e };
				this.pressOutId = setTimeout((): void => {
					this.pressOutId = -1;
					fire(held);
				}, wait) as int32;
			} else {
				fire(e);
			}
		}
		this.activateTime = -1;
	}

	private measure(): void {
		const host = this.host;
		if (host === null || this.node === null) { return; }
		const read = (host as Host).measureInWindow;
		if (read === null) { return; }
		const result = (read as (node: HostNode) => Result<MeasureRect, MeasureError>)(this.node as HostNode);
		if (result.ok) {
			const r = result.value;
			if (r.x !== 0 || r.y !== 0 || r.width !== 0 || r.height !== 0) { this.region = r; }
		}
	}

	private cancelLongPress(): void {
		if (this.longPressId >= 0) { clearTimeout(this.longPressId); }
		this.longPressId = -1;
	}

	private cancelPressOut(): void {
		if (this.pressOutId >= 0) { clearTimeout(this.pressOutId); }
		this.pressOutId = -1;
	}
}
