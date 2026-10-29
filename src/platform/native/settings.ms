import { SettingsServices, installSettingsServices, settingsEvent } from "../../api/settingsServices";
import { AppEvent, appCall, onNativeAppEvent, presentValue } from "./appBridge";

function settingsGet(key: string): string | null {
	return presentValue(appCall("settings.get", key));
}

function settingsSet(values: string): void {
	appCall("settings.set", values);
}

function watchSettings(): void {
	appCall("settings.watch", "");
}

export const nativeSettingsServices: SettingsServices = { settingsGet, settingsSet, watchSettings };

installSettingsServices(nativeSettingsServices);
onNativeAppEvent(AppEvent.Settings, (value: string): void => { settingsEvent(); });
