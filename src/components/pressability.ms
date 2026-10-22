import { NeonEvent, neonEvent } from "../render/event";
import { onCleanup } from "../core/cleanup";
import { Accessor } from "../core/signal";
import { ClaimWatch, pressSwallowed, unwatchTouchClaim, watchTouchClaim } from "../render/responder";

// RN Pressability's two constants (Libraries/Pressability/Pressability.js):
// a press becomes a LONG press at 500ms, and a press stays visibly held for at
// least 130ms so a fast tap still shows feedback instead of flickering.
export const LONG_PRESS_DELAY_MS = 500;
const MIN_PRESS_DURATION_MS = 130;

export interface PressConfig {
	onPress: ((e: NeonEvent) => void) | null;
	onPressIn: ((e: NeonEvent) => void) | null;
	onPressOut: ((e: NeonEvent) => void) | null;
	onLongPress: ((e: NeonEvent) => void) | null;
	onHoverIn: ((e: NeonEvent) => void) | null;
	onHoverOut: ((e: NeonEvent) => void) | null;
	delayLongPress: Accessor<number>;
}

export interface PressEvents {
	onPress: ((e: NeonEvent) => void) | null;
	onPointerDown: ((e: NeonEvent) => void) | null;
	onPointerUp: ((e: NeonEvent) => void) | null;
	onPointerEnter: ((e: NeonEvent) => void) | null;
	onPointerLeave: ((e: NeonEvent) => void) | null;
	onPointerCancel: ((e: NeonEvent) => void) | null;
}

// RN grants one responder per touch, the innermost that asks; nested pressables
// hear one bubbling pointerdown, so the first to start a press claims that event.
let claimedDown: NeonEvent | null = null;

function call(handler: ((e: NeonEvent) => void) | null, e: NeonEvent): void {
	if (handler !== null) { (handler as (x: NeonEvent) => void)(e); }
}

// Two tiers, chosen once at build time from the props the caller actually
// declared. `onPress` alone stays ONE click listener — the common button pays
// nothing for gestures it never asked for. Declaring any of pressIn/pressOut/
// longPress opts into the state machine, which then OWNS the press: it tracks
// pointer down/up/leave itself, because "did this press become a long press"
// is not a question the host's click event can answer.
export function pressEvents(config: PressConfig): PressEvents {
	const { onPress, onPressIn, onPressOut, onLongPress, onHoverIn, onHoverOut } = config;
	const wantsGestures = onPressIn !== null || onPressOut !== null || onLongPress !== null;

	if (!wantsGestures) {
		const press: ((e: NeonEvent) => void) | null = onPress === null ? null : (e: NeonEvent): void => {
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
	let outPending: NeonEvent | null = null;
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
	const releaseOut = (e: NeonEvent): void => {
		if (minHeld) { call(onPressOut, e); } else { outPending = e; }
	};
	const down = (e: NeonEvent): void => {
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
				call(onPressOut, held as NeonEvent);
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
	const up = (e: NeonEvent): void => {
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
	const cancel = (e: NeonEvent): void => {
		if (state === 0) { return; }
		settle();
		releaseOut(e);
	};
	watch = new ClaimWatch((): void => { cancel(neonEvent("pointercancel")); });
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
		onPointerLeave: (e: NeonEvent): void => {
			cancel(e);
			call(onHoverOut, e);
		},
		onPointerCancel: cancel,
	};
}
