import { HapticsServices, installHapticsServices } from "../../api/hapticsServices";
import { niHapticsCommand } from "./commands.h";
import { AppCommand, appCall } from "./appBridge";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/device.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/device");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		return niHapticsCommand(name, arg);
	}
} else {
	const command: AppCommand = appCall;
}

function haptic(kind: string, style: string): void {
	command("haptics." + kind, style);
}

export const nativeHapticsServices: HapticsServices = { haptic };

installHapticsServices(nativeHapticsServices);
