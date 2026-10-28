import { NeonEvent, neonEvent } from "../render/event";
import { onCleanup } from "../core/cleanup";
import { Accessor } from "../core/signal";
import { ClaimWatch, pressSwallowed, unwatchTouchClaim, watchTouchClaim } from "../render/responder";

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

export function pointerCancel(): NeonEvent {
	return neonEvent("pointercancel");
}

function call<E extends NeonEvent>(handler: ((e: E) => void) | null, e: E): void {
	if (handler !== null) { (handler as (x: E) => void)(e); }
}

// Two tiers, chosen once at build time from the props the caller actually
// declared. `onPress` alone stays ONE click listener — the common button pays
// nothing for gestures it never asked for. Declaring any of pressIn/pressOut/
// longPress opts into the state machine, which then OWNS the press: it tracks
// pointer down/up/leave itself, because "did this press become a long press"
// is not a question the host's click event can answer.
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

	let state = 0;           // 0 idle · 1 pressing · 2 long-pressing
	let longId = -1;
	let minId = -1;
	let minHeld = false;
	let outPending: E | null = null;
	let watch: ClaimWatch | null = null;

	const cancelTimer = (id: number): void => {
		if (id >= 0) { clearTimeout(id); }
	};
	const settle = (): void => {
		cancelTimer(longId);
		longId = -1;
		state = 0;
		unwatchTouchClaim(watch as ClaimWatch);
	};
	// RN _deactivate: pressOut waits out the remainder of the minimum hold,
	// so a 10ms tap still shows ~130ms of pressed state.
	const releaseOut = (e: E): void => {
		if (minHeld) { call(onPressOut, e); } else { outPending = e; }
	};
	const down = (e: E): void => {
		if (state !== 0 || claimedDown === e) { return; }
		state = 1;
		claimedDown = e;
		watchTouchClaim(watch as ClaimWatch);
		minHeld = false;
		outPending = null;
		call(onPressIn, e);
		minId = setTimeout((): void => {
			minHeld = true;
			const held = outPending;
			if (held !== null) {
				outPending = null;
				call(onPressOut, held as E);
			}
		}, MIN_PRESS_DURATION_MS) as int32;
		if (onLongPress !== null) {
			longId = setTimeout((): void => {
				if (state !== 1) { return; }
				state = 2;
				call(onLongPress, e);
			}, config.delayLongPress()) as int32;
		}
	};
	// RN: `isPressCanceledByLongPress` — a press that already fired
	// onLongPress does NOT also fire onPress, so a context menu and the
	// primary action never both run off one gesture.
	const up = (e: E): void => {
		if (state === 0) { return; }
		const wasLong = state === 2;
		settle();
		releaseOut(e);
		if (wasLong && onLongPress !== null) { return; }
		if (pressSwallowed(e)) { return; }
		call(onPress, e);
	};
	// Leaving the element (or the host cancelling) ends the press WITHOUT
	// firing onPress — RN's press-rect exit, minus the rect measurement.
	const cancel = (e: E): void => {
		if (state === 0) { return; }
		settle();
		releaseOut(e);
	};
	watch = new ClaimWatch((): void => { cancel(cancelled()); });
	onCleanup((): void => {
		cancelTimer(longId);
		cancelTimer(minId);
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
