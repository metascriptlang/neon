import { setFrameDriver, useManualFrames } from "../../src/animation/frame";
import { LayoutAnimation, LayoutAnimationConfig, takeLayoutAnimation } from "../../src/motion/layoutAnimation";

class Calls {
	ended: int32 = 0;
	failed: int32 = 0;
}

function configure(config: LayoutAnimationConfig, calls: Calls): void {
	LayoutAnimation.configureNext(
		config,
		(): void => { calls.ended += 1; },
		(): void => { calls.failed += 1; },
	);
}

test "a config Fabric cannot parse reports onAnimationDidFail, animates nothing, and still ends" {
	const frames = useManualFrames();
	const cases: LayoutAnimationConfig[] = [
		{ duration: 100, create: { type: "linear", property: null, duration: null, delay: null, springDamping: null, initialVelocity: null } },
		{ duration: 100, delete: { type: "linear", property: null, duration: null, delay: null, springDamping: null, initialVelocity: null } },
		{ duration: 100, update: { type: null, property: null, duration: null, delay: null, springDamping: null, initialVelocity: null } },
	];
	for (const config of cases) {
		const calls = new Calls();
		configure(config, calls);
		assert calls.failed === 1, "the failure is reported at once";
		assert takeLayoutAnimation() === null, "nothing is armed for the next commit";
		frames.runAll();
		assert calls.ended === 1, "RN's race timer still reports the end";
	}
	setFrameDriver(null);
}
