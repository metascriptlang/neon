import { KeyboardMetrics, useKeyboard, useWindowDimensions } from "../render/environment";
import { EventSubscription, onChange } from "./subscription";
import { appServices } from "./services";

export type KeyboardEventName =
	"keyboardWillShow" | "keyboardDidShow" | "keyboardWillHide" | "keyboardDidHide" |
	"keyboardWillChangeFrame" | "keyboardDidChangeFrame";

export interface KeyboardEventCoordinates {
	screenX: number;
	screenY: number;
	width: number;
	height: number;
}

export interface KeyboardEvent {
	duration: number;
	easing: string;
	endCoordinates: KeyboardEventCoordinates;
	isEventFromThisApp: boolean;
}

function eventFor(metrics: KeyboardMetrics): KeyboardEvent {
	const window = useWindowDimensions()();
	return {
		duration: 0,
		easing: "keyboard",
		endCoordinates: {
			screenX: 0,
			screenY: window.height - metrics.height,
			width: window.width,
			height: metrics.height,
		},
		isEventFromThisApp: true,
	};
}

// RN's Keyboard. Hosts publish one keyboard height, so the Will/Did pairs fire together
// once the height has changed: the show events when it becomes visible, the hide events
// when it goes, the frame events on every change.
export class Keyboard {
	static addListener(
		eventName: KeyboardEventName,
		callback: (event: KeyboardEvent) => void,
	): EventSubscription {
		const name: string = eventName;
		let wasVisible = useKeyboard()().visible;
		return onChange(useKeyboard(), (metrics: KeyboardMetrics): void => {
			const shown = metrics.visible && !wasVisible;
			const hidden = !metrics.visible && wasVisible;
			wasVisible = metrics.visible;
			const fires = match (name) {
				"keyboardWillShow" | "keyboardDidShow" => shown,
				"keyboardWillHide" | "keyboardDidHide" => hidden,
				_ => true,
			};
			if (fires) { callback(eventFor(metrics)); }
		});
	}

	static dismiss(): void {
		appServices("Keyboard.dismiss").dismissKeyboard();
	}

	static isVisible(): boolean {
		return useKeyboard()().visible;
	}

	static metrics(): KeyboardEventCoordinates | null {
		const metrics = useKeyboard()();
		if (!metrics.visible) { return null; }
		return eventFor(metrics).endCoordinates;
	}
}
