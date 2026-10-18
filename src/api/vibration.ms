import { vibrationServices } from "./vibrationServices";

when (js && !server) {
	import "../platform/browser/vibration";
} else when (ios || android) {
	import "../platform/native/vibration";
}

export class Vibration {
	static vibrate(pattern: number | number[] = 400, repeat: boolean = false): void {
		const steps: int32[] = [];
		if (typeof pattern === "number") {
			steps.push(0);
			steps.push(Math.round(pattern as number) as int32);
		} else {
			for (const step of pattern as number[]) { steps.push(Math.round(step) as int32); }
		}
		vibrationServices("Vibration.vibrate").vibrate(steps, repeat);
	}

	static cancel(): void {
		vibrationServices("Vibration.cancel").cancelVibration();
	}
}
