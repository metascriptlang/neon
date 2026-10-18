import { HapticsServices, installHapticsServices } from "../../api/hapticsServices";
import { niHapticsCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/device.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/device");
}

function command(name: string, arg: string): string {
	const reply: string = niHapticsCommand(name, arg);
	return reply;
}

function haptic(kind: string, style: string): void {
	command("haptics." + kind, style);
}

export const nativeHapticsServices: HapticsServices = { haptic };

installHapticsServices(nativeHapticsServices);
