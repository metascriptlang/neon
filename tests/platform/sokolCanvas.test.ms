import {
	runCanvas, canvasOptions, canvasFrameCounts,
} from "../../src/platform/sokol/canvas";
import {
	requestFrame, requestInputFrame, setFrameDriver,
} from "../../src/animation/frame";
import { Void, View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";

when (voidDummy) {
	test "the canvas delivers input and animation before its first paint" {
		setFrameDriver(null);
		const log: string[] = [];
		const paints: number[] = [];
		const opts = canvasOptions(200, 100);
		opts.font = "../void/assets/font.ttf";
		let result: int32 = -1;
		let failure = "";
		try { result = runCanvas(opts, (): NeonNode => {
			requestFrame((time: number): void => {
				log.push("animation");
				paints.push(canvasFrameCounts()[2]);
				requestFrame((next: number): void => { log.push("next frame"); });
			});
			requestInputFrame((time: number): void => {
				log.push("input");
				paints.push(canvasFrameCounts()[2]);
			});
			return <Void><View style={{ width: 20, height: 10 }} /></Void>;
		}); } catch (e) { failure = e.message; }
		setFrameDriver(null);
		assert failure === "", failure;
		assert result === 0;
		assert log.join(",") === "input,animation", log.join(",");
		assert paints.join(",") === "0,0", paints.join(",");
		assert canvasFrameCounts()[0] === 1;
		assert canvasFrameCounts()[2] === 1;
	}
}
