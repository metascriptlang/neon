import { Accessor, createSignal } from "../core/signal";
import { flush } from "../core/runtime";
import { EventSubscription, Listeners, onChange } from "./subscription";
import { appServices } from "./services";
import { Platform } from "./platform";
import { ElementHandle } from "../render/measure";
import {
	AccessibilityFlag, accessibilityServices, listenAccessibility, listenAccessibilityFlags,
} from "./accessibilityServices";

when (js && !server) {
	import "../platform/browser/accessibilityInfo";
} else when (ios || android) {
	import "../platform/native/accessibilityInfo";
}

export type AccessibilityChangeEventName =
	"screenReaderChanged" | "reduceMotionChanged" | "boldTextChanged" | "grayscaleChanged" |
	"invertColorsChanged" | "reduceTransparencyChanged" | "darkerSystemColorsChanged" |
	"highTextContrastChanged" | "accessibilityServiceChanged";

export interface AccessibilityAnnouncementFinishedEvent {
	announcement: string;
	success: boolean;
}

interface FlagEvent {
	name: string;
	enabled: boolean;
}

const flagEvents = new Listeners<FlagEvent>();
const announcements = new Listeners<AccessibilityAnnouncementFinishedEvent>();

const IOS_ONLY_EVENTS: string[] = ["boldTextChanged", "reduceTransparencyChanged", "darkerSystemColorsChanged"];
const ANDROID_ONLY_EVENTS: string[] = ["highTextContrastChanged", "accessibilityServiceChanged"];

function onAndroid(): boolean {
	return Platform.OS === "android";
}

async function platformFlag(api: string, name: AccessibilityFlag, android: boolean, other: boolean): Promise<boolean> {
	if (onAndroid() ? !android : !other) { return false; }
	return await accessibilityServices(api).flag(name);
}

function supported(eventName: string): boolean {
	return !(onAndroid() ? IOS_ONLY_EVENTS : ANDROID_ONLY_EVENTS).includes(eventName);
}

const [screenReader, setScreenReader] = createSignal<boolean>(false);
const [reduceMotion, setReduceMotion] = createSignal<boolean>(false);

export class AccessibilityInfo {
	static async isScreenReaderEnabled(): Promise<boolean> {
		return await accessibilityServices("AccessibilityInfo.isScreenReaderEnabled").screenReaderEnabled();
	}

	static async isReduceMotionEnabled(): Promise<boolean> {
		return await accessibilityServices("AccessibilityInfo.isReduceMotionEnabled").reduceMotionEnabled();
	}

	static async isBoldTextEnabled(): Promise<boolean> {
		return await platformFlag("AccessibilityInfo.isBoldTextEnabled", "boldText", false, true);
	}

	static async isGrayscaleEnabled(): Promise<boolean> {
		return await platformFlag("AccessibilityInfo.isGrayscaleEnabled", "grayscale", true, true);
	}

	static async isInvertColorsEnabled(): Promise<boolean> {
		return await platformFlag("AccessibilityInfo.isInvertColorsEnabled", "invertColors", true, true);
	}

	static async isReduceTransparencyEnabled(): Promise<boolean> {
		return await platformFlag("AccessibilityInfo.isReduceTransparencyEnabled", "reduceTransparency", false, true);
	}

	static async isHighTextContrastEnabled(): Promise<boolean> {
		return await platformFlag("AccessibilityInfo.isHighTextContrastEnabled", "highTextContrast", true, false);
	}

	static async isDarkerSystemColorsEnabled(): Promise<boolean> {
		return await platformFlag("AccessibilityInfo.isDarkerSystemColorsEnabled", "darkerSystemColors", false, true);
	}

	static async prefersCrossFadeTransitions(): Promise<boolean> {
		return await platformFlag("AccessibilityInfo.prefersCrossFadeTransitions", "crossFade", false, true);
	}

	static async isAccessibilityServiceEnabled(): Promise<boolean> {
		if (!onAndroid()) { throw new Error("isAccessibilityServiceEnabled is only available on Android"); }
		return await accessibilityServices("AccessibilityInfo.isAccessibilityServiceEnabled").flag("accessibilityService");
	}

	static async getRecommendedTimeoutMillis(originalTimeout: number): Promise<number> {
		if (!onAndroid()) { return originalTimeout; }
		const services = accessibilityServices("AccessibilityInfo.getRecommendedTimeoutMillis");
		return await services.recommendedTimeoutMillis(originalTimeout as int32);
	}

	// RN spells this addEventListener("announcementFinished", …); parked on ~/metascript/.inbox/compiler/2026-10-16-class-overload-signature-without-a-body-parses-as-an-empty-method.md
	static addAnnouncementFinishedListener(
		handler: (event: AccessibilityAnnouncementFinishedEvent) => void,
	): EventSubscription {
		return onAndroid() ? { remove: (): void => {} } : announcements.add(handler);
	}

	static addEventListener(
		eventName: AccessibilityChangeEventName,
		handler: (enabled: boolean) => void,
	): EventSubscription {
		if (!supported(eventName)) { return { remove: (): void => {} }; }
		if (eventName !== "screenReaderChanged" && eventName !== "reduceMotionChanged") {
			return flagEvents.add((event: FlagEvent): void => {
				if (event.name === eventName) { handler(event.enabled); }
			});
		}
		const name: string = eventName;
		const source: Accessor<boolean> = name === "reduceMotionChanged" ?
			reduceMotion :
			screenReader;
		return onChange(source, handler);
	}

	static setAccessibilityFocus(element: ElementHandle): void {
		element.accessibilityFocus();
	}

	static announceForAccessibility(announcement: string): void {
		appServices("AccessibilityInfo.announceForAccessibility").announce(announcement);
	}

	static announceForAccessibilityWithOptions(announcement: string, options: { queue?: boolean }): void {
		const queue = options.queue;
		if (onAndroid() || queue === undefined) {
			appServices("AccessibilityInfo.announceForAccessibilityWithOptions").announce(announcement);
			return;
		}
		accessibilityServices("AccessibilityInfo.announceForAccessibilityWithOptions").announceWithQueue(announcement, queue);
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

export function publishAccessibilityFlag(name: string, enabled: boolean): void {
	flush((): void => { flagEvents.emit({ name, enabled }); });
}

export function publishAnnouncementFinished(announcement: string, success: boolean): void {
	flush((): void => { announcements.emit({ announcement, success }); });
}

listenAccessibility(publishScreenReader, publishReduceMotion);
listenAccessibilityFlags(publishAccessibilityFlag, publishAnnouncementFinished);
