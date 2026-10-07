import { AlertRequest, AppServices, ShareRequest, installAppServices, ALERT_DISMISSED } from "../../api/services";
import { publishPlatform } from "../../api/platform";
import { publishScale, publishScreen } from "../../api/dimensions";
import { publishAppState } from "../../api/appState";
import { publishReduceMotion } from "../../api/accessibilityInfo";

extern class BrowserClipboard {
	extern readText(): Promise<string>;
	extern writeText(text: cstring): Promise<void>;
}

interface BrowserShareData {
	title: string;
	text: string;
	url: string;
}

extern class BrowserScreen {
	width: number;
	height: number;
}

extern class BrowserElement {
	textContent: cstring;
	extern blur(): void;
	extern setAttribute(name: cstring, value: cstring): void;
	extern appendChild(child: BrowserElement): void;
}

extern class BrowserEvent {}

extern class BrowserMediaQuery {
	matches: boolean;
	extern addEventListener(name: cstring, handler: (e: BrowserEvent) => void): void;
}

extern class navigator {
	static clipboard: BrowserClipboard;
	static extern share(data: BrowserShareData): Promise<void>;
	static extern vibrate(pattern: number[]): boolean;
}

extern class window {
	static devicePixelRatio: number;
	static screen: BrowserScreen;
	static extern alert(text: cstring): void;
	static extern confirm(text: cstring): boolean;
	static extern open(url: cstring, target: cstring, features: cstring): void;
	static extern matchMedia(query: cstring): BrowserMediaQuery;
}

extern class location {
	static href: string;
}

extern class document {
	static visibilityState: string;
	static activeElement: BrowserElement | null;
	static body: BrowserElement;
	static extern createElement(tag: cstring): BrowserElement;
	static extern addEventListener(name: cstring, handler: (e: BrowserEvent) => void): void;
}

extern function canShare(unused: int32): boolean from "(#, typeof navigator.share === 'function')";

let lastCopied = "";
let announcer: BrowserElement | null = null;

function cancelIndex(request: AlertRequest): int32 {
	for (let i = 0; i < request.buttons.length; i += 1) {
		if (request.buttons[i].style === "cancel") { return i as int32; }
	}
	return ALERT_DISMISSED;
}

function confirmIndex(request: AlertRequest): int32 {
	for (let i = request.buttons.length - 1; i >= 0; i -= 1) {
		if (request.buttons[i].style !== "cancel") { return i as int32; }
	}
	return (request.buttons.length as int32) - 1;
}

function alert(request: AlertRequest): void {
	const text = request.message === "" ? request.title : request.title + "\n\n" + request.message;
	if (request.buttons.length < 2) {
		window.alert(text);
		request.done(0);
		return;
	}
	request.done(window.confirm(text) ? confirmIndex(request) : cancelIndex(request));
}

async function shareThroughNavigator(request: ShareRequest): Promise<void> {
	try {
		await navigator.share({ title: request.title, text: request.message, url: request.url });
		request.done("sharedAction", "");
	} catch (e) {
		request.done("dismissedAction", "");
	}
}

async function readClipboard(): Promise<string> {
	try {
		return await navigator.clipboard.readText();
	} catch (e) {
		return lastCopied;
	}
}

async function writeClipboard(text: string): Promise<void> {
	try {
		await navigator.clipboard.writeText(text);
	} catch (e) {
		lastCopied = text;
	}
}

function vibrate(pattern: int32[], repeat: boolean): void {
	const steps: number[] = [0];
	for (const step of pattern) { steps.push(step as number); }
	try {
		navigator.vibrate(steps);
	} catch (e) {
		return;
	}
}

function announce(text: string): void {
	if (announcer === null) {
		const region = document.createElement("div");
		region.setAttribute("aria-live", "polite");
		region.setAttribute("style", "position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)");
		document.body.appendChild(region);
		announcer = region;
	}
	(announcer as BrowserElement).textContent = text;
}

const services: AppServices = {
	dismissKeyboard: (): void => {
		const focused = document.activeElement;
		if (focused !== null) { focused.blur(); }
	},
	alert,
	openURL: async (url: string): Promise<boolean> => {
		window.open(url, "_blank", "noopener");
		return true;
	},
	canOpenURL: async (url: string): Promise<boolean> => { return true; },
	initialURL: async (): Promise<string> => { return location.href; },
	openSettings: async (): Promise<boolean> => { return false; },
	share: (request: ShareRequest): void => {
		if (!canShare(0)) { throw new Error("Share is not supported in this browser"); }
		shareThroughNavigator(request);
	},
	vibrate,
	cancelVibration: (): void => { vibrate([], false); },
	getClipboard: readClipboard,
	setClipboard: (text: string): void => {
		lastCopied = text;
		writeClipboard(text);
	},
	screenReaderEnabled: async (): Promise<boolean> => { return false; },
	reduceMotionEnabled: async (): Promise<boolean> => {
		return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
	},
	announce,
	exitApp: (): void => {},
};

let installed = false;

function publishVisibility(): void {
	publishAppState(document.visibilityState === "hidden" ? "background" : "active");
}

export function installBrowserAppServices(): void {
	if (installed) { return; }
	installed = true;
	installAppServices(services);
	publishPlatform("", false);
	publishScale(window.devicePixelRatio, 1);
	publishScreen(window.screen.width, window.screen.height);
	publishVisibility();
	document.addEventListener("visibilitychange", (e: BrowserEvent): void => { publishVisibility(); });
	const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
	publishReduceMotion(motion.matches);
	motion.addEventListener("change", (e: BrowserEvent): void => { publishReduceMotion(motion.matches); });
}
