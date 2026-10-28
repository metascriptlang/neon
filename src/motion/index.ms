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
	MotionClip,
	MotionDocument,
	numberValue,
	colorValue,
	linearKeyframe,
	validate,
} from "./document";
export { interpolate, sampleTrack } from "./evaluate";
export { Clock, ManualClock } from "./clock";
