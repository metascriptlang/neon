export type AccessibilityFlag =
	"boldText" | "grayscale" | "invertColors" | "reduceTransparency" | "highTextContrast" |
	"darkerSystemColors" | "crossFade" | "accessibilityService";

export interface AccessibilityServices {
	screenReaderEnabled: () => Promise<boolean>;
	reduceMotionEnabled: () => Promise<boolean>;
	flag: (name: AccessibilityFlag) => Promise<boolean>;
	recommendedTimeoutMillis: (original: int32) => Promise<int32>;
	announceWithQueue: (text: string, queue: boolean) => void;
}

let installed: AccessibilityServices | null = null;
let screenReaderListener: (enabled: boolean) => void = (enabled: boolean): void => {};
let reduceMotionListener: (enabled: boolean) => void = (enabled: boolean): void => {};

let flagListener: (name: string, enabled: boolean) => void = (name: string, enabled: boolean): void => {};
let announcementListener: (text: string, success: boolean) => void = (text: string, success: boolean): void => {};

export function installAccessibilityServices(services: AccessibilityServices | null): void {
	installed = services;
}

export function accessibilityServices(api: string): AccessibilityServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}

export function listenAccessibility(screenReader: (enabled: boolean) => void, reduceMotion: (enabled: boolean) => void): void {
	screenReaderListener = screenReader;
	reduceMotionListener = reduceMotion;
}

export function screenReaderEvent(enabled: boolean): void {
	screenReaderListener(enabled);
}

export function reduceMotionEvent(enabled: boolean): void {
	reduceMotionListener(enabled);
}

export function listenAccessibilityFlags(flag: (name: string, enabled: boolean) => void, announcement: (text: string, success: boolean) => void): void {
	flagListener = flag;
	announcementListener = announcement;
}

export function accessibilityFlagEvent(name: string, enabled: boolean): void {
	flagListener(name, enabled);
}

export function announcementFinishedEvent(text: string, success: boolean): void {
	announcementListener(text, success);
}
