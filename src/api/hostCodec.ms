import { LocaleFields, LocaleSnapshot } from "./services";

const FIELD = "\u001f";
const RECORD = "\u001e";

// The localization reply every host encodes the same way: the calendar record
// (calendar, time zone, 24-hour clock 1/0, first weekday 1 = Sunday), then one record per preferred locale.
export function decodeLocalization(value: string): LocaleSnapshot {
	const records = value.split(RECORD);
	const calendar = records[0].split(FIELD);
	if (calendar.length !== 4) { throw new Error("Localization: the host sent a malformed calendar: " + records[0]); }
	const locales: LocaleFields[] = [];
	for (let i = 1; i < records.length; i += 1) {
		const fields = records[i].split(FIELD);
		if (fields.length !== 11) { throw new Error("Localization: the host sent a malformed locale: " + records[i]); }
		locales.push({
			languageTag: fields[0],
			languageCode: fields[1],
			scriptCode: fields[2],
			regionCode: fields[3],
			textDirection: fields[4],
			decimalSeparator: fields[5],
			groupingSeparator: fields[6],
			measurementSystem: fields[7],
			currencyCode: fields[8],
			currencySymbol: fields[9],
			temperatureUnit: fields[10],
		});
	}
	return {
		locales,
		calendar: calendar[0],
		timeZone: calendar[1],
		uses24hourClock: calendar[2] === "1",
		firstWeekday: parseInt(calendar[3]) as int32,
	};
}

