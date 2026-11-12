when (windows && !js) {
	import "../../src/platform/windows/library";
	import { nfwSetup, nfwOrder, nfwRequests, nfwStage } from "./windowsFrameOrder.h";
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
}
