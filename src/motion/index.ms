export {
	MOTION_VERSION,
	ValueKind,
	MotionColor,
	MotionValue,
	MotionHandles,
	MotionKeyframe,
	MotionTrack,
	MotionSlotMapping,
	MotionPlacement,
	MotionLabel,
	MotionClip,
	MotionDocument,
	numberValue,
	colorValue,
	linearKeyframe,
	findClip,
	validate,
} from "./document";
export {
	StaggerFrom,
	StaggerGrid,
	StaggerOptions,
	resolvePosition,
	stagger,
	staggerOptions,
} from "./compose";
export { interpolate, sampleTrack } from "./evaluate";
export { Clock, ManualClock } from "./clock";
export { MotionBinding, MotionOptions, MotionPlayer, motionOptions } from "./player";
export { Composition, MotionTarget } from "./target";
export { SpringKind, SpringConfig, SpringSimulation, springByStiffness, springByDuration, createSpring } from "./spring";
export { DecayConfig, DecaySimulation, decayConfig, createDecay } from "./decay";
export { MotionPolicy, ReduceMotion, shouldReduce } from "./policy";
export {
	AnimatedValue,
	AnimationKind,
	AnimationSpec,
	TimingOptions,
	timing,
	spring,
	decay,
	sequence,
	delay,
	repeat,
} from "./value";
