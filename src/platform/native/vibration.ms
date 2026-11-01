import { VibrationServices, installVibrationServices } from "../../api/vibrationServices";
import { AppCommand, FIELD, appCall } from "./appBridge";
import { niVibrationCommand } from "./commands.h";

when (ios) {
	@compile("../ios/vibration.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
	@passL("-framework AudioToolbox");
}

when (ios || android) {
	function command(name: string, arg: string): string {
		return niVibrationCommand(name, arg) as string;
	}
} else {
	const command: AppCommand = appCall;
}

function vibrate(pattern: int32[], repeat: boolean): void {
	let steps = "";
	for (const step of pattern) { steps += (steps === "" ? "" : ",") + step.toString(); }
	command("vibrate", (repeat ? "1" : "0") + FIELD + steps);
}

export const nativeVibrationServices: VibrationServices = {
	vibrate,
	cancelVibration: (): void => { command("vibrate.cancel", ""); },
};

installVibrationServices(nativeVibrationServices);
