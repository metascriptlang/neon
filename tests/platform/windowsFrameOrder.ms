when (windows && !js) {
	import "../../src/platform/windows/library";
	import { nfwSetup, nfwOrder, nfwRequests, nfwStage, nfwScrollFrame, nfwReportedScroll, nfwScrollReports } from "./windowsFrameOrder.h";
	@compile("./windowsFrameOrder.cpp");
	@compile("../../src/platform/native/loop.c");
	@passL("-ld3d11");
	@passL("-ldcomp");
	@passL("-ld2d1");

	test "Windows runs its frame before queued loop work" {
		const ready = nfwSetup();
		assert ready === 0, `${nfwStage() as string}: ${ready}`;
		const order = nfwOrder(0);
		assert order === 12, `frame=1, loop=2: ${order}`;
	}

	test "a Windows post-frame loop write requests the following frame" {
		const ready = nfwSetup();
		assert ready === 0, `${nfwStage() as string}: ${ready}`;
		const order = nfwOrder(1);
		assert order === 12, `frame=1, loop=2: ${order}`;
		assert nfwRequests() === 2;
	}

	test "Windows samples an animated scroll at target time before the app frame" {
		const ready = nfwSetup();
		assert ready === 0, `${nfwStage() as string}: ${ready}`;
		const offset = nfwScrollFrame(0, 10000.0);
		assert offset === 120, `scroll offset at app frame: ${offset}`;
		assert nfwScrollReports() === 1;
		assert nfwReportedScroll() === offset;
	}

	test "Windows samples a wheel scroll at target time before the app frame" {
		const ready = nfwSetup();
		assert ready === 0, `${nfwStage() as string}: ${ready}`;
		const offset = nfwScrollFrame(1, 10000.0);
		assert offset === 120, `wheel offset at app frame: ${offset}`;
		assert nfwScrollReports() === 1;
		assert nfwReportedScroll() === offset;
	}

	test "a late Windows frame never samples a scroll before its start" {
		const ready = nfwSetup();
		assert ready === 0, `${nfwStage() as string}: ${ready}`;
		const offset = nfwScrollFrame(0, -1000.0);
		assert offset === 0, `pre-start scroll offset: ${offset}`;
		assert nfwScrollReports() === 0;
	}
}
