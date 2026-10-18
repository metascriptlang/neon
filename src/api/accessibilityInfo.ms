import { Accessor, createSignal } from "../core/signal";
import { flush } from "../core/runtime";
import { EventSubscription, onChange } from "./subscription";
import { appServices } from "./services";
import { accessibilityServices, listenAccessibility } from "./accessibilityServices";

when (js && !server) {
	import "../platform/browser/accessibilityInfo";
} else when (ios || android) {
	import "../platform/native/accessibilityInfo";
}

export type AccessibilityChangeEventName = "screenReaderChanged" | "reduceMotionChanged";

const [screenReader, setScreenReader] = createSignal<boolean>(false);
const [reduceMotion, setReduceMotion] = createSignal<boolean>(false);

export class AccessibilityInfo {
	static async isScreenReaderEnabled(): Promise<boolean> {
		return await accessibilityServices("AccessibilityInfo.isScreenReaderEnabled").screenReaderEnabled();
	}

	static async isReduceMotionEnabled(): Promise<boolean> {
		return await accessibilityServices("AccessibilityInfo.isReduceMotionEnabled").reduceMotionEnabled();
	}

	static addEventListener(
		eventName: AccessibilityChangeEventName,
		handler: (enabled: boolean) => void,
	): EventSubscription {
		const name: string = eventName;
		const source: Accessor<boolean> = name === "reduceMotionChanged" ?
			reduceMotion :
			screenReader;
		return onChange(source, handler);
	}

	static announceForAccessibility(announcement: string): void {
		appServices("AccessibilityInfo.announceForAccessibility").announce(announcement);
	}
}

export function useScreenReaderEnabled(): Accessor<boolean> {
	return screenReader;
}

export function publishScreenReader(enabled: boolean): void {
	flush((): void => {
		if (screenReader() !== enabled) { setScreenReader(enabled); }
	});
}

export function publishReduceMotion(enabled: boolean): void {
	flush((): void => {
		if (reduceMotion() !== enabled) { setReduceMotion(enabled); }
	});
}

listenAccessibility(publishScreenReader, publishReduceMotion);
