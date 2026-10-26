import { SettingsServices, installSettingsServices, settingsEvent } from "../../api/settingsServices";
import { AppEvent, appCall, onNativeAppEvent } from "./appBridge";

const PRESENT = "=";

function settingsGet(key: string): string | null {
	const reply = appCall("settings.get", key);
	return reply.startsWith(PRESENT) ? reply.substring(1, reply.length) : null;
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
