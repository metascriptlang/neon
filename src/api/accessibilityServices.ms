export interface AccessibilityServices {
	screenReaderEnabled: () => Promise<boolean>;
	reduceMotionEnabled: () => Promise<boolean>;
}

let installed: AccessibilityServices | null = null;
let screenReaderListener: (enabled: boolean) => void = (enabled: boolean): void => {};
let reduceMotionListener: (enabled: boolean) => void = (enabled: boolean): void => {};

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
