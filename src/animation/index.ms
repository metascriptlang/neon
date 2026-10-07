// Import from here, not ./animated alone: methods of AnimatedValue resolve only when
// the caller's imports reach ./nodes (compiler card
// 2026-10-07-methods-of-a-class-from-an-unimported-module-are-not-found.md).
export {
	Animated, CompositeAnimation, useAnimatedValue, TimingConfig, TimingXYConfig, SpringConfig, SpringXYConfig,
	DecayConfig, DecayXYConfig, ParallelConfig, LoopAnimationConfig, EventMapping, EventConfig,
} from "./animated";
export {
	AnimatedNode, AnimatedValue, AnimatedValueXY, AnimatedInterpolation, AnimatedStringInterpolation,
	ValueState, ValueListener, ExtrapolateType, InterpolationConfig, StringInterpolationConfig, ValueXYInit, LayoutXY,
} from "./nodes";
export { Animation, EndResult, EndCallback, TimingAnimation, SpringAnimation, DecayAnimation } from "./animation";
export { Easing, EasingFunction, bezier } from "./easing";
export {
	LayoutAnimation, LayoutAnimationPresets, LayoutAnimationConfig, LayoutAnimationAnim, LayoutAnimationType,
	LayoutAnimationProperty,
} from "./layoutAnimation";
export { Presence, PresenceProps, PresenceType } from "./presence";
export { FrameDriver, ManualFrames, setFrameDriver, useManualFrames, requestFrame, cancelFrame, frameNow } from "./frame";
