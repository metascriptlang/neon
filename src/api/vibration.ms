import { INT32_MAX, checkedInt32 } from "./hostCodec";
import { vibrationServices } from "./vibrationServices";

when (js && !server) {
	import "../platform/browser/vibration";
} else when (ios || android) {
	import "../platform/native/vibration";
} else when (macos || windows || linux) {
	import "../platform/ion/vibration";
}

function milliseconds(field: string, value: number): int32 {
	return checkedInt32("Vibration.vibrate", field, Math.round(value), 0, INT32_MAX);
}

export class Vibration {
	static vibrate(pattern: number | number[] = 400, repeat: boolean = false): void {
		const steps: int32[] = [];
		if (typeof pattern === "number") {
			steps.push(0);
			steps.push(milliseconds("pattern", pattern));
		} else {
			for (let i = 0; i < pattern.length; i += 1) {
				steps.push(milliseconds(`pattern[${i}]`, pattern[i]));
			}
		}
		vibrationServices("Vibration.vibrate").vibrate(steps, repeat);
	}

	static cancel(): void {
		vibrationServices("Vibration.cancel").cancelVibration();
	}
}
