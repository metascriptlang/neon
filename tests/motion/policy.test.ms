import { MotionPolicy, ReduceMotion, shouldReduce } from "../../src/motion/policy";

test "System follows the policy the host sets, Always and Never ignore it" {
	const policy = new MotionPolicy();
	assert !policy.reducedMotion, "motion is full until the host says otherwise";
	assert !shouldReduce(ReduceMotion.System, policy);
	assert shouldReduce(ReduceMotion.Always, policy);
	assert !shouldReduce(ReduceMotion.Never, policy);
	policy.reducedMotion = true;
	assert shouldReduce(ReduceMotion.System, policy);
	assert shouldReduce(ReduceMotion.Always, policy);
	assert !shouldReduce(ReduceMotion.Never, policy);
}

test "two policies are independent" {
	const reduced = new MotionPolicy(true);
	const full = new MotionPolicy(false);
	assert shouldReduce(ReduceMotion.System, reduced);
	assert !shouldReduce(ReduceMotion.System, full);
}
