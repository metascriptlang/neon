import {
	AccessibilityFlag, AccessibilityServices, accessibilityFlagEvent, announcementFinishedEvent,
	installAccessibilityServices, reduceMotionEvent, screenReaderEvent,
} from "../../api/accessibilityServices";
import { AppEvent, FIELD, appCall, flagText, onNativeAppEvent, onNativeAppStart } from "./appBridge";
import { niAccessibilityCommand } from "./commands.h";

when (ios) {
	@compile("../ios/accessibility.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		const reply: string = niAccessibilityCommand(name, arg);
		return reply;
	}
} else {
	function command(name: string, arg: string): string {
		return appCall(name, arg);
	}
}

function screenReader(): boolean {
	return command("a11y.screenReader", "") === "1";
}

function reduceMotion(): boolean {
	return command("a11y.reduceMotion", "") === "1";
}

export const nativeAccessibilityServices: AccessibilityServices = {
	screenReaderEnabled: async (): Promise<boolean> => { return screenReader(); },
	reduceMotionEnabled: async (): Promise<boolean> => { return reduceMotion(); },
	flag: async (name: AccessibilityFlag): Promise<boolean> => { return command("a11y." + name, "") === "1"; },
	recommendedTimeoutMillis: async (original: int32): Promise<int32> => {
		return parseInt(command("a11y.timeout", original.toString())) as int32;
	},
	announceWithQueue: (text: string, queue: boolean): void => {
		command("a11y.announceQueue", flagText(queue) + FIELD + text);
	},
};

function onAccessibilityEvent(value: string): void {
	const fields = value.split(FIELD);
	if (fields[0] === "announcementFinished") {
		announcementFinishedEvent(fields[1], fields[2] === "1");
		return;
	}
	accessibilityFlagEvent(fields[0], fields[1] === "1");
}

installAccessibilityServices(nativeAccessibilityServices);
onNativeAppEvent(AppEvent.ScreenReader, (value: string): void => { screenReaderEvent(value === "1"); });
onNativeAppEvent(AppEvent.ReduceMotion, (value: string): void => { reduceMotionEvent(value === "1"); });
onNativeAppEvent(AppEvent.Accessibility, onAccessibilityEvent);
onNativeAppStart((): void => {
	screenReaderEvent(screenReader());
	reduceMotionEvent(reduceMotion());
});
