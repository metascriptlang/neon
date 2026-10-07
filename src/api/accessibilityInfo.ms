import { Accessor, createSignal } from "../core/signal";
import { EventSubscription, onChange } from "./subscription";
import { appServices } from "./services";

export type AccessibilityChangeEventName = "screenReaderChanged" | "reduceMotionChanged";

const [screenReader, setScreenReader] = createSignal<boolean>(false);
const [reduceMotion, setReduceMotion] = createSignal<boolean>(false);

export class AccessibilityInfo {
	static async isScreenReaderEnabled(): Promise<boolean> {
		return await appServices("AccessibilityInfo.isScreenReaderEnabled").screenReaderEnabled();
	}

	static async isReduceMotionEnabled(): Promise<boolean> {
		return await appServices("AccessibilityInfo.isReduceMotionEnabled").reduceMotionEnabled();
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
	if (screenReader() !== enabled) { setScreenReader(enabled); }
}

export function publishReduceMotion(enabled: boolean): void {
	if (reduceMotion() !== enabled) { setReduceMotion(enabled); }
}
