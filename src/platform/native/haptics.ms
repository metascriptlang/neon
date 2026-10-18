import { HapticsServices, installHapticsServices } from "../../api/hapticsServices";
import { appCall } from "./appBridge";
import { niHapticsCommand } from "../ios/commands.h";

when (ios) {
	@compile("../ios/device.m", "-fobjc-arc");

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
