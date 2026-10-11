import { LocaleFields, LocaleSnapshot, appServices } from "./services";

export interface Locale {
	languageTag: string;
	languageCode: string | null;
	languageScriptCode: string | null;
	regionCode: string | null;
	languageRegionCode: string | null;
	textDirection: string | null;
	digitGroupingSeparator: string | null;
	decimalSeparator: string | null;
	measurementSystem: string | null;
	currencyCode: string | null;
	currencySymbol: string | null;
	temperatureUnit: string | null;
}

export interface Calendar {
	calendar: string | null;
	timeZone: string | null;
	uses24hourClock: boolean | null;
	firstWeekday: number | null;
}

export interface NumberFormatSettings {
	decimalSeparator: string;
	groupingSeparator: string;
}

export interface LocalizeLocale {
	languageCode: string;
	scriptCode: string | null;
	countryCode: string;
	languageTag: string;
	isRTL: boolean;
}

function given(text: string): string | null {
	return text === "" ? null : text;
}

function snapshot(api: string): LocaleSnapshot {
	return appServices(api).localization();
}

function locale(fields: LocaleFields): Locale {
	return {
		languageTag: fields.languageTag,
		languageCode: given(fields.languageCode),
		languageScriptCode: given(fields.scriptCode),
		regionCode: given(fields.regionCode),
		languageRegionCode: given(fields.regionCode),
		textDirection: given(fields.textDirection),
		digitGroupingSeparator: given(fields.groupingSeparator),
		decimalSeparator: given(fields.decimalSeparator),
		measurementSystem: given(fields.measurementSystem),
		currencyCode: given(fields.currencyCode),
		currencySymbol: given(fields.currencySymbol),
		temperatureUnit: given(fields.temperatureUnit),
	};
}

export function getLocales(): Locale[] {
	const locales: Locale[] = [];
	for (const fields of snapshot("getLocales").locales) { locales.push(locale(fields)); }
	return locales;
}

export function getCalendars(): Calendar[] {
	const now = snapshot("getCalendars");
	return [{
		calendar: given(now.calendar),
		timeZone: given(now.timeZone),
		uses24hourClock: now.uses24hourClock,
		firstWeekday: now.firstWeekday as number,
	}];
}

function first(api: string): LocaleFields {
	const locales = snapshot(api).locales;
	if (locales.length === 0) { throw new Error(api + ": the host reported no locale"); }
	return locales[0];
}

export function getTimeZone(): string {
	return snapshot("getTimeZone").timeZone;
}

export function uses24HourClock(): boolean {
	return snapshot("uses24HourClock").uses24hourClock;
}

export function usesMetricSystem(): boolean {
	return first("usesMetricSystem").measurementSystem === "metric";
}

export function getTemperatureUnit(): string {
	const unit = first("getTemperatureUnit").temperatureUnit;
	return unit === "" ? "celsius" : unit;
}

export function getCountry(): string {
	return first("getCountry").regionCode;
}

export function getCurrencies(): string[] {
	const currencies: string[] = [];
	for (const fields of snapshot("getCurrencies").locales) {
		if (fields.currencyCode !== "" && currencies.indexOf(fields.currencyCode) < 0) { currencies.push(fields.currencyCode); }
	}
	return currencies;
}

export function getNumberFormatSettings(): NumberFormatSettings {
	const fields = first("getNumberFormatSettings");
	return { decimalSeparator: fields.decimalSeparator, groupingSeparator: fields.groupingSeparator };
}

export function getLocalizeLocales(): LocalizeLocale[] {
	const locales: LocalizeLocale[] = [];
	for (const fields of snapshot("getLocalizeLocales").locales) {
		locales.push({
			languageCode: fields.languageCode,
			scriptCode: given(fields.scriptCode),
			countryCode: fields.regionCode,
			languageTag: fields.languageTag,
			isRTL: fields.textDirection === "rtl",
		});
	}
	return locales;
}
