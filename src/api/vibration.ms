import { appServices } from "./services";

// RN's Vibration. A number vibrates that many milliseconds (iOS ignores the length, as
// RN); an array alternates pause and vibration, starting with a pause.
export class Vibration {
	static vibrate(pattern: number | number[] = 400, repeat: boolean = false): void {
		const steps: int32[] = [];
		if (typeof pattern === "number") {
			steps.push(0);
			steps.push(Math.round(pattern as number) as int32);
		} else {
			for (const step of pattern as number[]) { steps.push(Math.round(step) as int32); }
		}
		appServices("Vibration.vibrate").vibrate(steps, repeat);
	}

	static cancel(): void {
		appServices("Vibration.cancel").cancelVibration();
	}
}
