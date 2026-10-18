import { LocaleSnapshot, LocalizationServices, installLocalizationServices } from "../../api/localizationServices";
import { decodeLocalization } from "../../api/hostCodec";
import { appCall } from "./appBridge";
import { niLocaleCommand } from "../ios/commands.h";

when (ios) {
	@compile("../ios/device.m", "-fobjc-arc");

	function command(name: string, arg: string): string {
		const reply: string = niLocaleCommand(name, arg);
		return reply;
	}
} else {
	function command(name: string, arg: string): string {
		return appCall(name, arg);
	}
}

function localization(): LocaleSnapshot {
	return decodeLocalization(command("locale.info", ""));
}

export const nativeLocalizationServices: LocalizationServices = { localization };

installLocalizationServices(nativeLocalizationServices);
