import {
	AccessibilityServices, installAccessibilityServices, reduceMotionEvent, screenReaderEvent,
} from "../../api/accessibilityServices";
import { AppEvent, onNativeAppEvent, onNativeAppStart } from "./appBridge";
import { niAccessibilityCommand } from "./commands.h";

when (ios) {
	@compile("../ios/accessibility.m", "-fobjc-arc");
}

function command(name: string, arg: string): string {
	const reply: string = niAccessibilityCommand(name, arg);
	return reply;
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
};

installAccessibilityServices(nativeAccessibilityServices);
onNativeAppEvent(AppEvent.ScreenReader, (value: string): void => { screenReaderEvent(value === "1"); });
onNativeAppEvent(AppEvent.ReduceMotion, (value: string): void => { reduceMotionEvent(value === "1"); });
onNativeAppStart((): void => {
	screenReaderEvent(screenReader());
	reduceMotionEvent(reduceMotion());
});
