import { I18nState, I18nServices, installI18nServices } from "../../api/i18nServices";

const state: I18nState = {
	allowRTL: true, forceRTL: false, swapLeftAndRightInRTL: true,
	supportsRtl: false, deviceRTL: false, localeIdentifier: "",
};

function setPref(name: string, value: boolean): void {}

installI18nServices({ state: (): I18nState => { return state; }, setPref });
