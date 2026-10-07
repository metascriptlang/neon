import { ColorScheme, useColorScheme } from "../render/environment";
import { EventSubscription, onChange } from "./subscription";

export interface AppearancePreferences {
	colorScheme: ColorScheme;
}

// RN's Appearance, over the scheme the host publishes (`useColorScheme`).
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
