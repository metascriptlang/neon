when (!js) {
	import { createNativeHost } from "../../src/platform/native/host";
	import {
		requestFrame, requestInputFrame,
	} from "../../src/animation/frame";
	import {
		nmEnableFrames, nmFrameRequested, nmFrame,
	} from "./nativeBridgeMock.h";
	@compile("./nativeBridgeMock.c");

	test "native display stamps reach input and animation through the host" {
		nmEnableFrames(1);
		createNativeHost();
		const target = performance.now() + 60000.0;
		let inputTime = -1.0;
		let motionTime = -1.0;
		let fromInputTime = -1.0;
		let order = "";
		requestInputFrame((time: number): void => {
			inputTime = time;
			order += "input;";
			requestFrame((stamp: number): void => { fromInputTime = stamp; });
		});
		requestFrame((time: number): void => {
			motionTime = time;
			order += "motion;";
		});
		assert nmFrameRequested() === 1;
		assert inputTime === -1.0 && motionTime === -1.0;
		assert nmFrame(target) === 1;
		assert inputTime === target;
		assert motionTime === target;
		assert fromInputTime === target;
		assert order === "input;motion;";
		assert nmFrameRequested() === 0;
		assert nmFrame(target + 1.0) === 0;

		requestFrame((time: number): void => { motionTime = time; });
		assert nmFrame(target - 10.0) === 1;
		assert motionTime === target;

		requestFrame((time: number): void => {
			motionTime = time;
			requestFrame((stamp: number): void => { motionTime = stamp; });
		});
		assert nmFrame(target + 16.0) === 1;
		assert motionTime === target + 16.0;
		assert nmFrameRequested() === 1;
		assert nmFrame(target + 32.0) === 1;
		assert motionTime === target + 32.0;
		assert nmFrameRequested() === 0;
		nmEnableFrames(0);
	}
}
