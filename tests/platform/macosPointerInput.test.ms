when (macos && !js) {
	import "../../src/platform/macos/library";
	@compile("./macosPointerInput.m", "-fobjc-arc");
	@compile("../../src/platform/native/loop.c");
	@passL("-framework CoreImage");
	import {
		npiBegin, npiDrag, npiTick, npiUp, npiResize, npiDetach,
		npiControl, npiReenter, npiUnregister, npiMoves, npiOrder,
		npiRequests, npiLastX, npiLastTime, npiShutdown,
	} from "./macosPointerInput.h";

	test "macOS keeps the last drag until the frame input phase" {
		npiBegin();
		npiDrag(20, 10);
		npiDrag(40, 12);
		assert npiMoves() === 0;
		npiTick();
		assert npiMoves() === 1;
		assert npiLastX() === 40;
		assert npiLastTime() === 12;
		assert npiOrder() === 48;
	}

	test "macOS drains a pending drag before mouse up" {
		npiBegin();
		npiDrag(20, 10);
		npiDrag(40, 12);
		npiUp();
		assert npiMoves() === 1;
		assert npiOrder() === 41;
		npiTick();
		assert npiMoves() === 1;
	}

	test "macOS drains a pending drag before resizing its root" {
		npiBegin();
		npiDrag(20, 10);
		npiDrag(40, 12);
		npiResize();
		assert npiMoves() === 1;
		assert npiLastX() === 40;
	}

	test "macOS drains a pending drag before a native control event" {
		npiBegin();
		npiDrag(20, 10);
		npiDrag(40, 12);
		npiControl();
		assert npiMoves() === 1;
		assert npiOrder() === 45;
	}

	test "macOS drops the pending drag when its root detaches" {
		npiBegin();
		npiDrag(20, 10);
		npiDetach();
		npiTick();
		assert npiMoves() === 0;
		assert npiOrder() === 8;
	}

	test "macOS rearms a drag queued during input delivery" {
		npiBegin();
		npiReenter();
		npiDrag(40, 12);
		npiTick();
		assert npiMoves() === 1;
		assert npiRequests() === 2;
		npiTick();
		assert npiMoves() === 2;
		assert npiLastX() === 70;
		assert npiLastTime() === 21;
		assert npiOrder() === 4848;
	}

	test "macOS drops a drag when the app shuts down" {
		npiBegin();
		npiDrag(40, 12);
		npiShutdown();
		npiTick();
		assert npiMoves() === 0;
		assert npiOrder() === 8;
	}

	test "macOS drops a drag after its touch handler unregisters" {
		npiBegin();
		npiDrag(40, 12);
		npiUnregister();
		npiTick();
		assert npiMoves() === 0;
		assert npiOrder() === 8;
	}
}
