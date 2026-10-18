// "" marks a field the platform does not report.
export interface LocaleFields {
	languageTag: string;
	languageCode: string;
	scriptCode: string;
	regionCode: string;
	textDirection: string;
	decimalSeparator: string;
	groupingSeparator: string;
	measurementSystem: string;
	currencyCode: string;
	currencySymbol: string;
	temperatureUnit: string;
}

export interface LocaleSnapshot {
	locales: LocaleFields[];
	calendar: string;
	timeZone: string;
	uses24hourClock: boolean;
	firstWeekday: int32;
}

export interface LocalizationServices {
	localization: () => LocaleSnapshot;
}

let installed: LocalizationServices | null = null;

export function installLocalizationServices(services: LocalizationServices | null): void {
	installed = services;
}

export function localizationServices(api: string): LocalizationServices {
	const services = installed;
	if (services === null) { throw new Error(`${api} is not available on this host`); }
	return services;
}
