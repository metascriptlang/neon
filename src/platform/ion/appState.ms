import { publishAppState } from "../../api/appState";
import { onWindowEvent, WindowEventFocused, WindowEventBlurred } from "../../../../ion/src/windowManager";

export function ionAppStateEvent(label: string, eventType: int32): void {
	if (eventType === WindowEventFocused) { publishAppState("active"); }
	if (eventType === WindowEventBlurred) { publishAppState("inactive"); }
}

onWindowEvent(ionAppStateEvent);
