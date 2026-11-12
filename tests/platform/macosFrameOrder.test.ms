when (macos && !js) {
	import "../../src/platform/macos/library";
	@compile("./macosFrameOrder.m", "-fobjc-arc");
	@compile("../../src/platform/native/loop.c");
	@passL("-framework CoreImage");
	import { nfmOrder, nfmRequests } from "./macosFrameOrder.h";

	test "macOS runs its frame before queued loop work" {
		const order = nfmOrder(0);
		assert order === 12, `frame=1, loop=2: ${order}`;
	}

	test "a macOS post-frame loop write requests the following frame" {
		const order = nfmOrder(1);
		assert order === 12, `frame=1, loop=2: ${order}`;
		assert nfmRequests() === 2;
	}
}
