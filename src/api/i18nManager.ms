import { i18nServices } from "./i18nServices";

when (js && !server) {
	import "../platform/browser/i18n";
} else when (ios || android) {
	import "../platform/native/i18n";
}

export interface I18nManagerConstants {
	isRTL: boolean;
	doLeftAndRightSwapInRTL: boolean;
	localeIdentifier: string | null;
}

export class I18nManager {
	static isRTL(): boolean {
		const s = i18nServices().state();
		return s.supportsRtl && (s.forceRTL || (s.allowRTL && s.deviceRTL));
	}

	static doLeftAndRightSwapInRTL(): boolean {
		return i18nServices().state().swapLeftAndRightInRTL;
	}

	static getConstants(): I18nManagerConstants {
		const id = i18nServices().state().localeIdentifier;
		return { isRTL: I18nManager.isRTL(), doLeftAndRightSwapInRTL: I18nManager.doLeftAndRightSwapInRTL(), localeIdentifier: id === "" ? null : id };
	}

	static allowRTL(shouldAllow: boolean): void {
		i18nServices().setPref("allowRTL", shouldAllow);
	}

	static forceRTL(shouldForce: boolean): void {
		i18nServices().setPref("forceRTL", shouldForce);
	}

	static swapLeftAndRightInRTL(flipStyles: boolean): void {
		i18nServices().setPref("swapLeftAndRightInRTL", flipStyles);
	}
}
