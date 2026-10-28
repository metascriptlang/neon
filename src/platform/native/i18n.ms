import { I18nState, installI18nServices } from "../../api/i18nServices";
import { decodeI18n } from "../../api/hostCodec";
import { niLocaleCommand } from "./commands.h";
import { androidLibrary } from "../../../../ion/src/android";

when (ios) {
	@compile("../ios/device.m", "-fobjc-arc");
	@compile("../ios/wire.m", "-fobjc-arc");
} else when (android) {
	androidLibrary("../android/device");
}

function state(): I18nState {
	const reply: string = niLocaleCommand("i18n.info", "");
	return decodeI18n(reply);
}

function setPref(name: string, value: boolean): void {
	niLocaleCommand("i18n." + name, value ? "1" : "0");
}

installI18nServices({ state, setPref });
