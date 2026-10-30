import { Scene2D, group, local, paint } from "../../../void/src/void2d/node";
import { create } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { MotionDocument, ValueKind, linearKeyframe } from "../../src/motion/index";
import { MotionPlayer, motionOptions } from "../../src/motion/player";
import { VoidBindings, VoidClock } from "../../src/motion/void";

function slide(): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [
			{
				id: "main",
				duration: 400,
				tracks: [
					{
						slot: "box",
						property: "x",
						kind: ValueKind.Number,
						keyframes: [linearKeyframe("x0", 0, 0), linearKeyframe("x1", 400, 200)],
					},
					{
						slot: "box",
						property: "alpha",
						kind: ValueKind.Number,
						keyframes: [linearKeyframe("a0", 0, 0), linearKeyframe("a1", 400, 1)],
					},
				],
				placements: [],
				labels: [],
			},
		],
	};
}

const scene = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const node = scene.group();
const clock = new VoidClock();
const bindings = new VoidBindings();
bindings.node("box", node, ["x", "alpha"]);
const player = new MotionPlayer(slide(), bindings.bindings, motionOptions(clock.clock));
let frames: int32 = 0;
while (clock.pending() > 0) {
	clock.tick(0.1);
	frames += 1;
	console.log(`frame ${frames}: x ${node.local().x} alpha ${node.paint().alpha}`);
}
player.dispose();
