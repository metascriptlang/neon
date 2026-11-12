when (macos && !js) {
	import "../../src/platform/macos/library";
	@compile("./macosPointerInput.m", "-fobjc-arc");
	@compile("../../src/platform/native/loop.c");
	@passL("-framework CoreImage");
	import {
		npiBegin, npiDrag, npiTick, npiUp, npiResize, npiDetach,
		npiControl, npiReenter, npiUnregister, npiMoves, npiOrder,
		npiRequests, npiLastX, npiLastTime, npiShutdown,
		npiScroll, npiUnregisterScroll, npiReenterScroll,
		npiStopFromScroll, npiScrolls, npiScrollY, npiOffsetY,
		npiReleaseScroll,
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

	test "macOS applies native offsets now and reports once before frame" {
		npiBegin();
		npiScroll(20);
		npiScroll(40);
		assert npiOffsetY() === 40;
		assert npiScrolls() === 0;
		npiTick();
		assert npiScrolls() === 1;
		assert npiScrollY() === 40;
		assert npiOrder() === 68;
	}

	test "macOS preserves scroll then drag order in the input phase" {
		npiBegin();
		npiScroll(20);
		npiDrag(40, 12);
		assert npiScrolls() === 0;
		npiTick();
		assert npiOrder() === 648;
	}

	test "macOS preserves drag then scroll order in the input phase" {
		npiBegin();
		npiDrag(40, 12);
		npiScroll(20);
		npiTick();
		assert npiOrder() === 468;
	}

	test "macOS does not merge drags across a scroll report" {
		npiBegin();
		npiDrag(20, 10);
		npiScroll(20);
		npiDrag(40, 12);
		npiTick();
		assert npiMoves() === 2;
		assert npiOrder() === 4648;
	}

	test "macOS drains the latest scroll before a native control event" {
		npiBegin();
		npiScroll(20);
		npiScroll(40);
		npiControl();
		assert npiScrolls() === 1;
		assert npiScrollY() === 40;
		assert npiOrder() === 65;
	}

	test "macOS drops a pending scroll when its root detaches" {
		npiBegin();
		npiScroll(20);
		npiDetach();
		npiTick();
		assert npiScrolls() === 0;
		assert npiOrder() === 8;
	}

	test "macOS does not retain a released pending scroll target" {
		assert npiReleaseScroll() === 1;
		npiTick();
		assert npiScrolls() === 0;
		assert npiOrder() === 8;
	}

	test "macOS drops a pending scroll when its handler unregisters" {
		npiBegin();
		npiScroll(20);
		npiUnregisterScroll();
		npiTick();
		assert npiScrolls() === 0;
		assert npiOrder() === 8;
	}

	test "macOS drops a pending scroll on shutdown" {
		npiBegin();
		npiScroll(20);
		npiShutdown();
		npiTick();
		assert npiScrolls() === 0;
		assert npiOrder() === 8;
	}

	test "macOS rearms a native scroll changed during input delivery" {
		npiBegin();
		npiScroll(20);
		npiReenterScroll();
		npiTick();
		assert npiScrolls() === 1;
		assert npiScrollY() === 20;
		assert npiRequests() === 2;
		npiTick();
		assert npiScrolls() === 2;
		assert npiScrollY() === 80;
		assert npiOrder() === 6868;
	}

	test "macOS shutdown inside a scroll cancels the remaining input" {
		npiBegin();
		npiScroll(20);
		npiDrag(40, 12);
		npiScroll(60);
		npiStopFromScroll();
		npiTick();
		assert npiScrolls() === 1;
		assert npiMoves() === 0;
		assert npiOrder() === 68;
	}
}
