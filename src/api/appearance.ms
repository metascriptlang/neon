import { ColorScheme, useColorScheme } from "../render/environment";
import { EventSubscription, onChange } from "./subscription";

export interface AppearancePreferences {
	colorScheme: ColorScheme;
}

export class Appearance {
	static getColorScheme(): ColorScheme {
		return useColorScheme()();
	}

	static addChangeListener(
		listener: (preferences: AppearancePreferences) => void,
	): EventSubscription {
		return onChange(useColorScheme(), (scheme: ColorScheme): void => {
			listener({ colorScheme: scheme });
		});
	}
}
