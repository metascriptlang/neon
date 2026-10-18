import { HapticsServices, installHapticsServices } from "../../api/hapticsServices";
import { niHapticsCommand } from "./commands.h";
import { appCall } from "./appBridge";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/device.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/device");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		const reply: string = niHapticsCommand(name, arg);
		return reply;
	}
} else {
	function command(name: string, arg: string): string {
		return appCall(name, arg);
	}
}

function haptic(kind: string, style: string): void {
	command("haptics." + kind, style);
}

export const nativeHapticsServices: HapticsServices = { haptic };

installHapticsServices(nativeHapticsServices);
