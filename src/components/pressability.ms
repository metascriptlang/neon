import { NeonEvent, neonEvent } from "../render/event";
import { onCleanup } from "../core/cleanup";
import { Accessor } from "../core/signal";
import { ClaimWatch, pressSwallowed, unwatchTouchClaim, watchTouchClaim } from "../render/responder";
import { TimerHandle } from "./timerHandle";

// RN Pressability's two constants (Libraries/Pressability/Pressability.js):
// a press becomes a LONG press at 500ms, and a press stays visibly held for at
// least 130ms so a fast tap still shows feedback instead of flickering.
export const LONG_PRESS_DELAY_MS = 500;
const MIN_PRESS_DURATION_MS = 130;

export interface PressConfig<E extends NeonEvent> {
	onPress: ((e: E) => void) | null;
	onPressIn: ((e: E) => void) | null;
	onPressOut: ((e: E) => void) | null;
	onLongPress: ((e: E) => void) | null;
	onHoverIn: ((e: E) => void) | null;
	onHoverOut: ((e: E) => void) | null;
	delayLongPress: Accessor<number>;
}

export interface PressEvents<E extends NeonEvent> {
	onPress: ((e: E) => void) | null;
	onPointerDown: ((e: E) => void) | null;
	onPointerUp: ((e: E) => void) | null;
	onPointerEnter: ((e: E) => void) | null;
	onPointerLeave: ((e: E) => void) | null;
	onPointerCancel: ((e: E) => void) | null;
}

// RN grants one responder per touch, the innermost that asks; nested pressables
// hear one bubbling pointerdown, so the first to start a press claims that event.
let claimedDown: NeonEvent | null = null;

enum PressState {
	Idle,
	Pressing,
	LongPressing,
}

export function pointerCancel(): NeonEvent {
	return neonEvent("pointercancel");
}

function call<E extends NeonEvent>(handler: ((e: E) => void) | null, e: E): void {
	if (handler !== null) { handler(e); }
}

export function pressEvents<E extends NeonEvent>(config: PressConfig<E>, cancelled: () => E): PressEvents<E> {
	const { onPress, onPressIn, onPressOut, onLongPress, onHoverIn, onHoverOut } = config;
	const wantsGestures = onPressIn !== null || onPressOut !== null || onLongPress !== null;

	if (!wantsGestures) {
		const press: ((e: E) => void) | null = onPress === null ? null : (e: E): void => {
			if (!pressSwallowed(e)) { call(onPress, e); }
		};
		return {
			onPress: press, onPointerDown: null, onPointerUp: null,
			onPointerEnter: onHoverIn, onPointerLeave: onHoverOut, onPointerCancel: null,
		};
	}

	let state = PressState.Idle;
	const longTimer = new TimerHandle();
	const minTimer = new TimerHandle();
	let minHeld = false;
	let outPending: E | null = null;
	let watch: ClaimWatch | null = null;

	const settle = (): void => {
		longTimer.cancel();
		state = PressState.Idle;
		unwatchTouchClaim(watch as ClaimWatch);
	};
	// RN _deactivate: pressOut waits out the remainder of the minimum hold,
	// so a 10ms tap still shows ~130ms of pressed state.
	const releaseOut = (e: E): void => {
		if (minHeld) { call(onPressOut, e); } else { outPending = e; }
	};
	const down = (e: E): void => {
		if (state !== PressState.Idle || claimedDown === e) { return; }
		state = PressState.Pressing;
		claimedDown = e;
		watchTouchClaim(watch as ClaimWatch);
		minHeld = false;
		outPending = null;
		call(onPressIn, e);
		minTimer.start((): void => {
			minHeld = true;
			const held = outPending;
			if (held !== null) {
				outPending = null;
				call(onPressOut, held as E);
			}
		}, MIN_PRESS_DURATION_MS);
		if (onLongPress !== null) {
			longTimer.start((): void => {
				if (state !== PressState.Pressing) { return; }
				state = PressState.LongPressing;
				call(onLongPress, e);
			}, config.delayLongPress());
		}
	};
	// RN: `isPressCanceledByLongPress` — a press that already fired
	// onLongPress does NOT also fire onPress, so a context menu and the
	// primary action never both run off one gesture.
	const up = (e: E): void => {
		if (state === PressState.Idle) { return; }
		const wasLong = match (state) {
			PressState.LongPressing => true,
			PressState.Idle | PressState.Pressing => false,
		};
		settle();
		releaseOut(e);
		if (wasLong && onLongPress !== null) { return; }
		if (pressSwallowed(e)) { return; }
		call(onPress, e);
	};
	// Leaving the element (or the host cancelling) ends the press WITHOUT
	// firing onPress — RN's press-rect exit, minus the rect measurement.
	const cancel = (e: E): void => {
		if (state === PressState.Idle) { return; }
		settle();
		releaseOut(e);
	};
	watch = new ClaimWatch((): void => { cancel(cancelled()); });
	onCleanup((): void => {
		longTimer.cancel();
		minTimer.cancel();
		unwatchTouchClaim(watch as ClaimWatch);
	});
	return {
		onPress: null,
		onPointerDown: down,
		onPointerUp: up,
		onPointerEnter: onHoverIn,
		onPointerLeave: (e: E): void => {
			cancel(e);
			call(onHoverOut, e);
		},
		onPointerCancel: cancel,
	};
}
