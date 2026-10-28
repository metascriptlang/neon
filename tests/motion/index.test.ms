import {
	AnimatedValue,
	ManualClock,
	MotionDocument,
	MotionPlayer,
	MotionPolicy,
	MotionValue,
	ValueKind,
	createDecay,
	createSpring,
	decayConfig,
	linearKeyframe,
	motionOptions,
	springByStiffness,
	timing,
} from "../../src/motion/index";

function ramp(): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [
			{
				id: "main",
				duration: 1000,
				tracks: [
					{
						slot: "box",
						property: "x",
						kind: ValueKind.Number,
						keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", 1000, 100)],
					},
				],
				placements: [],
				labels: [],
			},
		],
	};
}

test "a headless program plays a document through the public entry alone" {
	const manual = new ManualClock();
	let last: float64 = -1;
	const player = new MotionPlayer(ramp(), [{
		slot: "box",
		property: "x",
		write: (value: MotionValue): void => { last = value.number; },
		read: null,
	}], motionOptions(manual.clock));
	manual.advance(250);
	assert Math.abs(last - 25) < 1e-6;
	manual.advance(750);
	assert Math.abs(last - 100) < 1e-6;
	assert manual.pending() === 0;
	player.dispose();
}

test "spring and decay simulations read through the same accessor names" {
	const s = createSpring(springByStiffness(), 0, 100);
	const d = createDecay(decayConfig(), 0, 500);
	assert s.position(0) === 0;
	assert d.position(0) === 0;
	assert s.position(5000) > 99.9;
	assert d.velocity(0) > 0;
	assert s.isDone(10000);
}

test "an animated value runs on a manual clock with an explicit policy" {
	const manual = new ManualClock();
	const policy = new MotionPolicy();
	const value = new AnimatedValue(0, manual.clock, policy);
	value.animate(timing(10, { duration: 100 }));
	manual.advance(16);
	manual.advance(200);
	assert value.get() === 10;
	assert manual.pending() === 0;
	value.dispose();
}
