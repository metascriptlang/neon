import { Accessor, createSignal } from "../core/signal";
import { EventSubscription, onChange } from "./subscription";
import { appServices } from "./services";

export type AccessibilityChangeEventName = "screenReaderChanged" | "reduceMotionChanged";

// Indexed, not destructured: module-scope destructuring temps collide in a JS bundle (compiler
// card 2026-10-08-js-bundle-module-scope-destructuring-temps-collide.md, WORKAROUND.md W6).
const screenReaderSignal = createSignal<boolean>(false);
const screenReader = screenReaderSignal[0];
const setScreenReader = screenReaderSignal[1];
const reduceMotionSignal = createSignal<boolean>(false);
const reduceMotion = reduceMotionSignal[0];
const setReduceMotion = reduceMotionSignal[1];

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
