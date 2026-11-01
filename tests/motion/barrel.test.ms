import {
	Host,
	HostNode,
	MotionPolicy,
	MotionSignals,
	NeonNode,
	Style,
	View,
	accessor,
	render,
	spring,
	timing,
	useAnimatedValue,
	useMotion,
} from "../../src/index";
import { mockHost } from "../../src/render/host";
import { framePending, setFrameDriver, useManualFrames } from "../../src/animation/frame";
import { Easing } from "pulse/src/easing";
import { ValueKind, linearKeyframe } from "pulse/src/document";

test "an app writes the documented motion path from the neon barrel alone" {
	const frames = useManualFrames();
	const signals = new MotionSignals();
	const opacity = signals.number("box", "opacity", 0);
	const scale = signals.number("box", "scale", 1);
	const x = signals.number("box", "translateX", 0);
	const host = mockHost();
	const root = host.createElement("root");
	let springSettled = false;
	let timingSettled = false;
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		useMotion({
			version: 1,
			root: "main",
			clips: [{
				id: "main",
				duration: 100,
				tracks: [{
					slot: "box",
					property: "opacity",
					kind: ValueKind.Number,
					keyframes: [linearKeyframe("o0", 0, 0), linearKeyframe("o1", 100, 1)],
				}],
				placements: [],
				labels: [],
			}],
		}, [signals.bindings[0]]);
		const scaled = useAnimatedValue(1, new MotionPolicy(), signals.target("box", "scale"))[1];
		scaled.animate(spring(2), (finished: boolean): void => { springSettled = finished; });
		const moved = useAnimatedValue(0, new MotionPolicy(), signals.target("box", "translateX"))[1];
		moved.animate(
			timing(40, { duration: 100, easing: Easing.linear }),
			(finished: boolean): void => { timingSettled = finished; },
		);
		View({ style: accessor((): Style => signals.style("box")) })(h, parent, before);
	};
	const dispose = render(app, host, root);
	frames.runAll();
	assert opacity() === 1 && scale() === 2 && x() === 40, `${opacity()} ${scale()} ${x()}`;
	assert springSettled && timingSettled;
	dispose();
	assert !framePending();
	setFrameDriver(null);
}
