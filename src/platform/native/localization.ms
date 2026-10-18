import { LocaleSnapshot, LocalizationServices, installLocalizationServices } from "../../api/localizationServices";
import { decodeLocalization } from "../../api/hostCodec";
import { niLocaleCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/device.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/device");
}

function command(name: string, arg: string): string {
	const reply: string = niLocaleCommand(name, arg);
	return reply;
}

function localization(): LocaleSnapshot {
	return decodeLocalization(command("locale.info", ""));
}

export const nativeLocalizationServices: LocalizationServices = { localization };

installLocalizationServices(nativeLocalizationServices);
